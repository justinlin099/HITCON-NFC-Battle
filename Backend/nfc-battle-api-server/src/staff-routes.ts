import { Hono } from "hono";
import {
  deletePrizeSnapshot,
  markPhishingEventsApplied,
  unmarkPhishingEventsApplied,
  writePrizeSnapshot,
} from "./freeze-snapshot-store";
import { isFreezingStale } from "./freeze";
import { RANK_THRESHOLD, STAMP_THRESHOLD } from "./game-config";
import {
  getGameState,
  markScoreboardFrozen,
  markScoreboardResumeInProgress,
  resetScoreboardToOpen,
  rollbackScoreboardFreeze,
  startScoreboardFreeze,
  type GameStateRow,
} from "./game-state";
import { requireAuth } from "./auth";
import { newFreezeId, nowIso } from "./ids";
import { hasOnlyKeys, isPlainObject, readJson, requiredString } from "./request";
import { errorResponse, success, successMessage } from "./responses";
import { requireStaffDangerToken, requireStaffRole } from "./staff";
import { replaceUserTag } from "./tag-store";
import type { AppEnv } from "./types";
import { getUserRow } from "./user-store";

const staffRoutes = new Hono<AppEnv>();
const FREEZE_SCOREBOARD_KEYS = new Set(["scoring_cutoff_at"]);
const REPLACE_USER_TAG_KEYS = new Set(["user_id", "new_physical_id"]);

staffRoutes.use("*", requireAuth, requireStaffRole);

staffRoutes.get("/scoreboard_status", requireStaffDangerToken, async (c) => {
  const state = await getGameState(c.env.DB);

  return success(c, scoreboardStatusData(state));
});

staffRoutes.post("/replace_user_tag", async (c) => {
  const request = validateReplaceUserTagRequest(await readJson(c));
  if (!request) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const user = await getUserRow(c.env.DB, request.user_id);
  if (!user) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  const result = await replaceUserTag(c.env.DB, request.user_id, request.new_physical_id);
  if (result.conflict) {
    return errorResponse(c, 409, "TAG_ALREADY_PAIRED", "This NFC tag is already paired.");
  }

  return successMessage(c, "User tag replaced successfully.");
});

staffRoutes.post("/freeze_scoreboard", requireStaffDangerToken, async (c) => {
  const request = await readOptionalFreezeRequest(c.req.raw);
  if (!request) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const freezeId = newFreezeId();
  const startedAt = nowIso();
  const scoringCutoffAt = request.scoring_cutoff_at ?? startedAt;
  if (scoringCutoffAt > startedAt) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  if (!(await startScoreboardFreeze(c.env.DB, freezeId, startedAt, scoringCutoffAt))) {
    return errorResponse(c, 409, "SCOREBOARD_ALREADY_FROZEN", "Scoreboard is already frozen.");
  }

  try {
    await writePrizeSnapshot(c.env.DB, freezeId, scoringCutoffAt);
    await markPhishingEventsApplied(c.env.DB, freezeId, scoringCutoffAt);
    const frozenAt = await transitionToFrozen(c.env.DB, freezeId);

    return success(c, {
      frozen: true,
      freeze_id: freezeId,
      scoring_cutoff_at: scoringCutoffAt,
      frozen_at: frozenAt,
      stamp_threshold: STAMP_THRESHOLD,
      rank_threshold: RANK_THRESHOLD,
    });
  } catch (error) {
    console.error("Failed to freeze scoreboard.", error);
    await rollbackFailedFreeze(c.env.DB, freezeId);
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }
});

staffRoutes.post("/resume_scoreboard", requireStaffDangerToken, async (c) => {
  const state = await getGameState(c.env.DB);
  const staleFreezing = isFreezingStale(
    state.state,
    state.freeze_started_at,
    state.freeze_timeout_seconds,
  );

  if (state.state !== "FROZEN" && !staleFreezing) {
    return errorResponse(c, 409, "SCOREBOARD_NOT_FROZEN", "Scoreboard is not frozen yet.");
  }

  if (state.freeze_id) {
    if (state.state === "FROZEN") {
      const resumeStarted = await markScoreboardResumeInProgress(
        c.env.DB,
        state.freeze_id,
        nowIso(),
      );
      if (!resumeStarted) {
        return errorResponse(c, 409, "SCOREBOARD_NOT_FROZEN", "Scoreboard is not frozen yet.");
      }
    }

    await deletePrizeSnapshot(c.env.DB, state.freeze_id);
    await unmarkPhishingEventsApplied(c.env.DB, state.freeze_id);
  }

  await resetScoreboardToOpen(c.env.DB, nowIso());

  return successMessage(c, "Scoreboard resumed.");
});

export default staffRoutes;

function scoreboardStatusData(state: GameStateRow) {
  return {
    state: state.state,
    freeze_id: state.freeze_id,
    freeze_started_at: state.freeze_started_at,
    scoring_cutoff_at: state.scoring_cutoff_at,
    frozen_at: state.frozen_at,
    freeze_timeout_seconds: state.freeze_timeout_seconds,
    freezing_stale: isFreezingStale(
      state.state,
      state.freeze_started_at,
      state.freeze_timeout_seconds,
    ),
  };
}

function validateReplaceUserTagRequest(value: unknown) {
  if (!isPlainObject(value) || !hasOnlyKeys(value, REPLACE_USER_TAG_KEYS)) {
    return null;
  }

  const userId = requiredString(value, "user_id");
  const newPhysicalId = requiredString(value, "new_physical_id");
  if (!userId || !newPhysicalId) {
    return null;
  }

  return {
    user_id: userId,
    new_physical_id: newPhysicalId,
  };
}

async function rollbackFailedFreeze(db: D1Database, freezeId: string) {
  const timestamp = nowIso();
  await deletePrizeSnapshot(db, freezeId);
  await unmarkPhishingEventsApplied(db, freezeId);
  await rollbackScoreboardFreeze(db, freezeId, timestamp);
}

async function transitionToFrozen(db: D1Database, freezeId: string) {
  const timestamp = nowIso();
  const transitioned = await markScoreboardFrozen(db, freezeId, timestamp);
  if (!transitioned) {
    throw new Error("Failed to transition scoreboard to FROZEN.");
  }

  const state = await getGameState(db);
  if (state.state !== "FROZEN" || state.freeze_id !== freezeId || state.frozen_at !== timestamp) {
    throw new Error("Scoreboard FROZEN transition did not persist.");
  }

  return timestamp;
}

async function readOptionalFreezeRequest(request: Request) {
  const text = await request.text();
  if (text.trim() === "") {
    return {};
  }

  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return null;
  }

  if (!isPlainObject(value) || !hasOnlyKeys(value, FREEZE_SCOREBOARD_KEYS)) {
    return null;
  }

  const scoringCutoffAt = value.scoring_cutoff_at;
  if (scoringCutoffAt === undefined) {
    return {};
  }

  if (typeof scoringCutoffAt !== "string" || Number.isNaN(Date.parse(scoringCutoffAt))) {
    return null;
  }

  return {
    scoring_cutoff_at: new Date(scoringCutoffAt).toISOString(),
  };
}
