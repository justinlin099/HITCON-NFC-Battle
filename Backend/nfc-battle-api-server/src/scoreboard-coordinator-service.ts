import {
  deletePrizeSnapshot,
  markPhishingEventsApplied,
  unmarkPhishingEventsApplied,
  writePrizeSnapshot,
} from "./freeze-snapshot-store";
import { isFreezingStale } from "./freeze";
import {
  getGameState,
  markScoreboardFrozen,
  markScoreboardResumeInProgress,
  resetScoreboardToOpen,
  rollbackScoreboardFreeze,
  startScoreboardFreeze,
} from "./game-state";
import { nowIso } from "./ids";
import {
  advanceLiveScoreboard,
  getFrozenScoreboardEntries,
  getLiveScoreboardBaseline,
  type ScoreboardSnapshotEntry,
  type ScoreboardSourceCursors,
} from "./scoreboard-store";
import type { AppBindings } from "./types";

export const SCOREBOARD_COORDINATOR_NAME = "global-scoreboard";

const SNAPSHOT_SCHEMA_VERSION = 1;
const MAX_SNAPSHOT_BYTES = 1_900_000;
const DEFAULT_REFRESH_SECONDS = 10;
const MIN_REFRESH_SECONDS = 1;
const MAX_REFRESH_SECONDS = 300;

type CoordinatorMode = "IDLE" | "FREEZING" | "RESUMING";

interface CoordinatorControl {
  schema_version: number;
  mode: CoordinatorMode;
  freeze_id: string | null;
  scoring_cutoff_at: string | null;
}

export interface ScoreboardSnapshot {
  schema_version: number;
  generation: string;
  generated_at: string;
  state: "OPEN" | "FROZEN";
  freeze_id: string | null;
  scoring_cutoff_at: string | null;
  entries: ScoreboardSnapshotEntry[];
  cursors: ScoreboardSourceCursors | null;
}

export interface StoredCoordinatorState {
  control: unknown;
  snapshot: unknown;
  pending_snapshot: unknown;
}

export interface ScoreboardCoordinatorStorage {
  readState(): Promise<StoredCoordinatorState>;
  writeState(update: Partial<StoredCoordinatorState>): Promise<void>;
}

export interface ScoreboardCoordinatorScheduler {
  schedule(delayMs: number): Promise<void>;
  stop(): Promise<void>;
}

export type ScoreboardPageReadResult =
  | {
      status: "READY";
      generated_at: string;
      frozen: boolean;
      freeze_id: string | null;
      scoring_cutoff_at: string | null;
      entries: ScoreboardSnapshotEntry[];
    }
  | { status: "FREEZING" }
  | { status: "UNAVAILABLE" };

export type ScoreboardReadResult = ScoreboardPageReadResult;

export type ScoreboardUserReadResult =
  | {
      status: "READY";
      generated_at: string;
      frozen: boolean;
      freeze_id: string | null;
      scoring_cutoff_at: string | null;
      entry: ScoreboardSnapshotEntry | null;
    }
  | { status: "FREEZING" }
  | { status: "UNAVAILABLE" };

export type FreezeScoreboardResult =
  | { status: "FROZEN"; frozen_at: string }
  | { status: "ALREADY_FROZEN" }
  | { status: "FAILED"; message: string };

export type ResumeScoreboardResult =
  | { status: "RESUMED" }
  | { status: "NOT_FROZEN" }
  | { status: "FAILED"; message: string };

export class ScoreboardCoordinatorService {
  private operationTail: Promise<void> = Promise.resolve();

  constructor(
    private readonly env: () => AppBindings,
    private readonly storage: ScoreboardCoordinatorStorage,
    private readonly scheduler: ScoreboardCoordinatorScheduler,
  ) {}

  async initialize() {
    const stored = await this.storage.readState();
    const control = validControl(stored.control);
    const snapshot = validSnapshot(stored.snapshot);

    if (control.mode !== "IDLE" || !snapshot || snapshot.state === "OPEN") {
      await this.scheduler.schedule(0);
    } else {
      await this.scheduler.stop();
    }
  }

  async readPage(offset: number, limit: number): Promise<ScoreboardPageReadResult> {
    const state = await this.storage.readState();
    const control = validControl(state.control);
    if (control.mode !== "IDLE") {
      return { status: "FREEZING" };
    }

    const snapshot = validSnapshot(state.snapshot);
    if (!snapshot) {
      await this.scheduler.schedule(0);
      return { status: "UNAVAILABLE" };
    }

    return {
      status: "READY",
      generated_at: snapshot.generated_at,
      frozen: snapshot.state === "FROZEN",
      freeze_id: snapshot.freeze_id,
      scoring_cutoff_at: snapshot.scoring_cutoff_at,
      entries: snapshot.entries.slice(offset, offset + limit),
    };
  }

  async readAll(): Promise<ScoreboardReadResult> {
    const state = await this.storage.readState();
    const control = validControl(state.control);
    if (control.mode !== "IDLE") {
      return { status: "FREEZING" };
    }

    const snapshot = validSnapshot(state.snapshot);
    if (!snapshot) {
      await this.scheduler.schedule(0);
      return { status: "UNAVAILABLE" };
    }

    return {
      status: "READY",
      generated_at: snapshot.generated_at,
      frozen: snapshot.state === "FROZEN",
      freeze_id: snapshot.freeze_id,
      scoring_cutoff_at: snapshot.scoring_cutoff_at,
      entries: snapshot.entries,
    };
  }

  async readUser(userId: string): Promise<ScoreboardUserReadResult> {
    const state = await this.storage.readState();
    const control = validControl(state.control);
    if (control.mode !== "IDLE") {
      return { status: "FREEZING" };
    }

    const snapshot = validSnapshot(state.snapshot);
    if (!snapshot) {
      await this.scheduler.schedule(0);
      return { status: "UNAVAILABLE" };
    }

    return {
      status: "READY",
      generated_at: snapshot.generated_at,
      frozen: snapshot.state === "FROZEN",
      freeze_id: snapshot.freeze_id,
      scoring_cutoff_at: snapshot.scoring_cutoff_at,
      entry: snapshot.entries.find((entry) => entry.user_id === userId) ?? null,
    };
  }

  refreshNow() {
    return this.runExclusive(() => this.synchronize());
  }

  watchdog() {
    return this.runExclusive(() => this.synchronize());
  }

  alarm() {
    return this.runExclusive(async () => {
      try {
        await this.synchronize();
      } catch (error) {
        console.error(JSON.stringify({
          level: "error",
          event: "scoreboard_refresh_failed",
          error: errorMessage(error),
        }));
        await this.scheduler.schedule(refreshIntervalMs(this.env()));
      }
    });
  }

  freeze(
    freezeId: string,
    startedAt: string,
    scoringCutoffAt: string,
  ): Promise<FreezeScoreboardResult> {
    return this.runExclusive(async () => {
      const db = this.env().DB;
      const state = await getGameState(db);
      if (state.state !== "OPEN") {
        return { status: "ALREADY_FROZEN" };
      }

      await this.storage.writeState({
        control: controlState("FREEZING", freezeId, scoringCutoffAt),
        pending_snapshot: null,
      });

      if (!(await startScoreboardFreeze(db, freezeId, startedAt, scoringCutoffAt))) {
        await this.storage.writeState({ control: idleControl(), pending_snapshot: null });
        return { status: "ALREADY_FROZEN" };
      }

      return this.finishFreeze(freezeId, scoringCutoffAt, false);
    });
  }

  resume(): Promise<ResumeScoreboardResult> {
    return this.runExclusive(async () => {
      const db = this.env().DB;
      const state = await getGameState(db);
      const staleFreezing = isFreezingStale(
        state.state,
        state.freeze_started_at,
        state.freeze_timeout_seconds,
      );

      if (state.state !== "FROZEN" && !staleFreezing) {
        return { status: "NOT_FROZEN" };
      }

      await this.storage.writeState({
        control: controlState("RESUMING", state.freeze_id, state.scoring_cutoff_at),
        pending_snapshot: null,
      });

      try {
        if (state.freeze_id) {
          if (state.state === "FROZEN") {
            const resumeStarted = await markScoreboardResumeInProgress(
              db,
              state.freeze_id,
              nowIso(),
            );
            if (!resumeStarted) {
              await this.storage.writeState({ control: idleControl() });
              return { status: "NOT_FROZEN" };
            }
          }

          await deletePrizeSnapshot(db, state.freeze_id);
          await unmarkPhishingEventsApplied(db, state.freeze_id);
        }

        await resetScoreboardToOpen(db, nowIso());
        await this.publishOpenBaseline();
        return { status: "RESUMED" };
      } catch (error) {
        await this.scheduler.schedule(0);
        return { status: "FAILED", message: errorMessage(error) };
      }
    });
  }

  private async synchronize() {
    const db = this.env().DB;
    const gameState = await getGameState(db);
    const stored = await this.storage.readState();
    const control = validControl(stored.control);
    const snapshot = validSnapshot(stored.snapshot);
    const pendingSnapshot = validSnapshot(stored.pending_snapshot);

    if (gameState.state === "OPEN") {
      if (control.mode !== "IDLE" || snapshot?.state !== "OPEN") {
        await this.publishOpenBaseline();
      } else {
        await this.publishOpenIncrement(snapshot);
      }
      return;
    }

    if (gameState.state === "FROZEN" && gameState.freeze_id) {
      if (
        control.mode === "FREEZING" &&
        pendingSnapshot?.state === "FROZEN" &&
        pendingSnapshot.freeze_id === gameState.freeze_id
      ) {
        await this.publishSnapshot(pendingSnapshot);
      } else if (
        snapshot?.state !== "FROZEN" ||
        snapshot.freeze_id !== gameState.freeze_id ||
        control.mode !== "IDLE"
      ) {
        await this.publishFrozenSnapshot(
          gameState.freeze_id,
          gameState.scoring_cutoff_at,
        );
      } else {
        await this.scheduler.stop();
      }
      return;
    }

    if (control.mode === "RESUMING") {
      await this.recoverResume(gameState.freeze_id);
      return;
    }

    await this.storage.writeState({
      control: controlState(
        "FREEZING",
        gameState.freeze_id,
        gameState.scoring_cutoff_at,
      ),
    });

    if (
      gameState.freeze_id &&
      gameState.scoring_cutoff_at &&
      Date.now() >= Date.parse(gameState.scoring_cutoff_at)
    ) {
      await this.finishFreeze(gameState.freeze_id, gameState.scoring_cutoff_at, true);
    } else {
      await this.scheduler.schedule(refreshIntervalMs(this.env()));
    }
  }

  private async publishOpenIncrement(snapshot: ScoreboardSnapshot) {
    if (!snapshot.cursors) {
      await this.publishOpenBaseline();
      return;
    }

    const next = await advanceLiveScoreboard(
      this.env().DB,
      snapshot.entries,
      snapshot.cursors,
    );
    if (!next) {
      await this.publishOpenBaseline();
      return;
    }

    const latestState = await getGameState(this.env().DB);
    if (latestState.state !== "OPEN") {
      await this.scheduler.schedule(0);
      return;
    }

    await this.publishSnapshot(makeSnapshot("OPEN", null, null, next.entries, next.cursors));
  }

  private async publishOpenBaseline() {
    const live = await getLiveScoreboardBaseline(this.env().DB);
    const latestState = await getGameState(this.env().DB);
    if (latestState.state !== "OPEN") {
      await this.scheduler.schedule(0);
      return;
    }

    await this.publishSnapshot(makeSnapshot("OPEN", null, null, live.entries, live.cursors));
  }

  private async publishFrozenSnapshot(freezeId: string, scoringCutoffAt: string | null) {
    const entries = await getFrozenScoreboardEntries(this.env().DB, freezeId);
    await this.publishSnapshot(
      makeSnapshot("FROZEN", freezeId, scoringCutoffAt, entries, null),
    );
  }

  private async finishFreeze(
    freezeId: string,
    scoringCutoffAt: string,
    resetPartialSnapshot: boolean,
  ): Promise<FreezeScoreboardResult> {
    const db = this.env().DB;

    try {
      if (resetPartialSnapshot) {
        await deletePrizeSnapshot(db, freezeId);
        await unmarkPhishingEventsApplied(db, freezeId);
      }

      await writePrizeSnapshot(db, freezeId, scoringCutoffAt);
      await markPhishingEventsApplied(db, freezeId, scoringCutoffAt);

      const entries = await getFrozenScoreboardEntries(db, freezeId);
      const pendingSnapshot = makeSnapshot(
        "FROZEN",
        freezeId,
        scoringCutoffAt,
        entries,
        null,
      );
      await this.storage.writeState({ pending_snapshot: pendingSnapshot });

      const frozenAt = nowIso();
      const transitioned = await markScoreboardFrozen(db, freezeId, frozenAt);
      if (!transitioned) {
        throw new Error("Failed to transition scoreboard to FROZEN.");
      }

      const state = await getGameState(db);
      if (state.state !== "FROZEN" || state.freeze_id !== freezeId || state.frozen_at !== frozenAt) {
        throw new Error("Scoreboard FROZEN transition did not persist.");
      }

      await this.publishSnapshot(pendingSnapshot);
      return { status: "FROZEN", frozen_at: frozenAt };
    } catch (error) {
      const state = await getGameState(db);
      if (state.state === "FROZEN" && state.freeze_id === freezeId && state.frozen_at) {
        const stored = await this.storage.readState();
        const pending = validSnapshot(stored.pending_snapshot);
        if (pending?.freeze_id === freezeId) {
          await this.publishSnapshot(pending);
        } else {
          await this.scheduler.schedule(0);
        }
        return { status: "FROZEN", frozen_at: state.frozen_at };
      }

      await deletePrizeSnapshot(db, freezeId);
      await unmarkPhishingEventsApplied(db, freezeId);
      await rollbackScoreboardFreeze(db, freezeId, nowIso());
      await this.storage.writeState({ control: idleControl(), pending_snapshot: null });
      await this.scheduler.schedule(0);
      return { status: "FAILED", message: errorMessage(error) };
    }
  }

  private async recoverResume(freezeId: string | null) {
    const db = this.env().DB;
    if (freezeId) {
      await deletePrizeSnapshot(db, freezeId);
      await unmarkPhishingEventsApplied(db, freezeId);
    }
    await resetScoreboardToOpen(db, nowIso());
    await this.publishOpenBaseline();
  }

  private async publishSnapshot(snapshot: ScoreboardSnapshot) {
    assertSnapshotSize(snapshot);
    await this.storage.writeState({
      snapshot,
      pending_snapshot: null,
      control: idleControl(),
    });

    console.log(JSON.stringify({
      level: "info",
      event: "scoreboard_snapshot_published",
      generation: snapshot.generation,
      generated_at: snapshot.generated_at,
      state: snapshot.state,
      freeze_id: snapshot.freeze_id,
      users: snapshot.entries.length,
    }));

    if (snapshot.state === "OPEN") {
      await this.scheduler.schedule(refreshIntervalMs(this.env()));
    } else {
      await this.scheduler.stop();
    }
  }

  private runExclusive<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.operationTail.then(operation, operation);
    this.operationTail = result.then(
      () => undefined,
      () => undefined,
    );
    return result;
  }
}

export function getScoreboardCoordinator(env: AppBindings) {
  return env.SCOREBOARD_COORDINATOR.getByName(SCOREBOARD_COORDINATOR_NAME);
}

function makeSnapshot(
  state: "OPEN" | "FROZEN",
  freezeId: string | null,
  scoringCutoffAt: string | null,
  entries: ScoreboardSnapshotEntry[],
  cursors: ScoreboardSourceCursors | null,
): ScoreboardSnapshot {
  return {
    schema_version: SNAPSHOT_SCHEMA_VERSION,
    generation: crypto.randomUUID(),
    generated_at: nowIso(),
    state,
    freeze_id: freezeId,
    scoring_cutoff_at: scoringCutoffAt,
    entries,
    cursors,
  };
}

function validSnapshot(value: unknown): ScoreboardSnapshot | null {
  if (
    !value ||
    typeof value !== "object" ||
    (value as Partial<ScoreboardSnapshot>).schema_version !== SNAPSHOT_SCHEMA_VERSION ||
    !Array.isArray((value as Partial<ScoreboardSnapshot>).entries)
  ) {
    return null;
  }

  const snapshot = value as ScoreboardSnapshot;
  return snapshot.state === "OPEN" || snapshot.state === "FROZEN" ? snapshot : null;
}

function validControl(value: unknown): CoordinatorControl {
  if (
    !value ||
    typeof value !== "object" ||
    (value as Partial<CoordinatorControl>).schema_version !== SNAPSHOT_SCHEMA_VERSION
  ) {
    return idleControl();
  }

  const control = value as CoordinatorControl;
  return control.mode === "IDLE" || control.mode === "FREEZING" || control.mode === "RESUMING"
    ? control
    : idleControl();
}

function idleControl(): CoordinatorControl {
  return controlState("IDLE", null, null);
}

function controlState(
  mode: CoordinatorMode,
  freezeId: string | null,
  scoringCutoffAt: string | null,
): CoordinatorControl {
  return {
    schema_version: SNAPSHOT_SCHEMA_VERSION,
    mode,
    freeze_id: freezeId,
    scoring_cutoff_at: scoringCutoffAt,
  };
}

function refreshIntervalMs(env: AppBindings) {
  const parsed = Number(env.SCOREBOARD_REFRESH_SECONDS);
  const seconds = Number.isInteger(parsed) && parsed >= MIN_REFRESH_SECONDS && parsed <= MAX_REFRESH_SECONDS
    ? parsed
    : DEFAULT_REFRESH_SECONDS;
  return seconds * 1000;
}

function assertSnapshotSize(snapshot: ScoreboardSnapshot) {
  const size = new TextEncoder().encode(JSON.stringify(snapshot)).byteLength;
  if (size > MAX_SNAPSHOT_BYTES) {
    throw new Error(`Scoreboard snapshot is too large (${size} bytes).`);
  }
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}
