import { DurableObject } from "cloudflare:workers";
import {
  ScoreboardCoordinatorService,
  type FreezeScoreboardResult,
  type ResumeScoreboardResult,
  type ScoreboardCoordinatorScheduler,
  type ScoreboardCoordinatorStorage,
  type ScoreboardReadResult,
  type ScoreboardPageReadResult,
  type ScoreboardUserReadResult,
  type StoredCoordinatorState,
} from "./scoreboard-coordinator-service";
import type { AppBindings } from "./types";

const CONTROL_KEY = "control";
const SNAPSHOT_KEY = "snapshot";
const PENDING_SNAPSHOT_KEY = "pending_snapshot";

export class ScoreboardCoordinator extends DurableObject<AppBindings> {
  private readonly service: ScoreboardCoordinatorService;

  constructor(ctx: DurableObjectState, env: AppBindings) {
    super(ctx, env);

    const storage = new DurableScoreboardStorage(ctx.storage);
    const scheduler = new DurableScoreboardScheduler(ctx.storage);
    this.service = new ScoreboardCoordinatorService(() => this.env, storage, scheduler);

    ctx.blockConcurrencyWhile(() => this.service.initialize());
  }

  readPage(offset: number, limit: number): Promise<ScoreboardPageReadResult> {
    return this.service.readPage(offset, limit);
  }

  readAll(): Promise<ScoreboardReadResult> {
    return this.service.readAll();
  }

  readUser(userId: string): Promise<ScoreboardUserReadResult> {
    return this.service.readUser(userId);
  }

  refreshNow(): Promise<void> {
    return this.service.refreshNow();
  }

  watchdog(): Promise<void> {
    return this.service.watchdog();
  }

  freeze(
    freezeId: string,
    startedAt: string,
    scoringCutoffAt: string,
  ): Promise<FreezeScoreboardResult> {
    return this.service.freeze(freezeId, startedAt, scoringCutoffAt);
  }

  resume(): Promise<ResumeScoreboardResult> {
    return this.service.resume();
  }

  alarm(): Promise<void> {
    return this.service.alarm();
  }
}

class DurableScoreboardStorage implements ScoreboardCoordinatorStorage {
  private state: StoredCoordinatorState = {
    control: undefined,
    snapshot: undefined,
    pending_snapshot: undefined,
  };
  private loadPromise: Promise<void> | null = null;

  constructor(private readonly storage: DurableObjectStorage) {}

  async readState(): Promise<StoredCoordinatorState> {
    await this.ensureLoaded();
    return this.state;
  }

  async writeState(update: Partial<StoredCoordinatorState>) {
    await this.ensureLoaded();
    const values: Record<string, unknown> = {};
    if ("control" in update) {
      values[CONTROL_KEY] = update.control;
    }
    if ("snapshot" in update) {
      values[SNAPSHOT_KEY] = update.snapshot;
    }
    if ("pending_snapshot" in update) {
      values[PENDING_SNAPSHOT_KEY] = update.pending_snapshot;
    }
    await this.storage.put(values);
    this.state = { ...this.state, ...update };
  }

  private ensureLoaded() {
    this.loadPromise ??= this.load();
    return this.loadPromise;
  }

  private async load() {
    const values = await this.storage.get([
      CONTROL_KEY,
      SNAPSHOT_KEY,
      PENDING_SNAPSHOT_KEY,
    ]);
    this.state = {
      control: values.get(CONTROL_KEY),
      snapshot: values.get(SNAPSHOT_KEY),
      pending_snapshot: values.get(PENDING_SNAPSHOT_KEY),
    };
  }
}

class DurableScoreboardScheduler implements ScoreboardCoordinatorScheduler {
  constructor(private readonly storage: DurableObjectStorage) {}

  async schedule(delayMs: number) {
    const scheduledAt = Date.now() + Math.max(0, delayMs);
    const current = await this.storage.getAlarm();
    if (current === null || scheduledAt < current) {
      await this.storage.setAlarm(scheduledAt);
    }
  }

  async stop() {
    if (await this.storage.getAlarm() !== null) {
      await this.storage.deleteAlarm();
    }
  }
}
