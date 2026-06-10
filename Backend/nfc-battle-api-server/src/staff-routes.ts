import { Hono } from "hono";
import { isFreezingStale } from "./freeze";
import {
  PHISHING_PENALTY,
  RANK_THRESHOLD,
  SCORE_PER_COLLECTION,
  STAMP_THRESHOLD,
} from "./game-config";
import {
  getGameState,
  markScoreboardFrozen,
  markScoreboardResumeInProgress,
  resetScoreboardToOpen,
  rollbackScoreboardFreeze,
  startScoreboardFreeze,
  type GameStateRow,
} from "./game-state";
import { newFreezeId, nowIso } from "./ids";
import { hasOnlyKeys, isPlainObject } from "./request";
import { errorResponse, success, successMessage } from "./responses";
import { requireStaffDangerToken } from "./staff";
import type { AppEnv } from "./types";

const staffRoutes = new Hono<AppEnv>();
const FREEZE_SCOREBOARD_KEYS = new Set(["scoring_cutoff_at"]);

staffRoutes.use("*", requireStaffDangerToken);

staffRoutes.get("/scoreboard_status", async (c) => {
  const state = await getGameState(c.env.DB);

  return success(c, scoreboardStatusData(state));
});

staffRoutes.post("/freeze_scoreboard", async (c) => {
  const request = await readOptionalFreezeRequest(c.req.raw);
  if (!request) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const freezeId = newFreezeId();
  const startedAt = nowIso();
  const scoringCutoffAt = request.scoring_cutoff_at ?? startedAt;

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

staffRoutes.post("/resume_scoreboard", async (c) => {
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

    await c.env.DB.prepare("DELETE FROM prize_results WHERE freeze_id = ?1")
      .bind(state.freeze_id)
      .run();
    await c.env.DB.prepare(
      `
      UPDATE phishing_events
      SET applied_freeze_id = NULL
      WHERE applied_freeze_id = ?1
      `,
    )
      .bind(state.freeze_id)
      .run();
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

async function writePrizeSnapshot(db: D1Database, freezeId: string, scoringCutoffAt: string) {
  await db
    .prepare(
      `
      WITH collection_counts AS (
        SELECT
          scanner_user_id AS user_id,
          COUNT(*) AS num_of_collection
        FROM collections
        WHERE first_collected_at <= ?7
        GROUP BY scanner_user_id
      ),
      phishing_counts AS (
        SELECT
          victim_user_id AS user_id,
          COUNT(*) AS num_of_phishing
        FROM phishing_events
        WHERE applied_freeze_id IS NULL AND created_at <= ?7
        GROUP BY victim_user_id
      ),
      stamp_counts AS (
        SELECT
          collections.scanner_user_id AS user_id,
          SUM(CASE WHEN collected.role = 'SPONSOR' THEN 1 ELSE 0 END) AS sponsor_count,
          SUM(CASE WHEN collected.role = 'COMMUNITY' THEN 1 ELSE 0 END) AS community_count
        FROM collections
        INNER JOIN users AS collected ON collected.user_id = collections.collected_user_id
        WHERE collections.first_collected_at <= ?7
        GROUP BY collections.scanner_user_id
      ),
      scored AS (
        SELECT
          users.user_id,
          (COALESCE(collection_counts.num_of_collection, 0) * ?2)
            - (COALESCE(phishing_counts.num_of_phishing, 0) * ?3) AS final_score,
          COALESCE(stamp_counts.sponsor_count, 0) AS sponsor_count,
          COALESCE(stamp_counts.community_count, 0) AS community_count
        FROM users
        LEFT JOIN collection_counts ON collection_counts.user_id = users.user_id
        LEFT JOIN phishing_counts ON phishing_counts.user_id = users.user_id
        LEFT JOIN stamp_counts ON stamp_counts.user_id = users.user_id
      ),
      ranked AS (
        SELECT
          ROW_NUMBER() OVER (ORDER BY final_score DESC, user_id ASC) AS rank,
          user_id,
          final_score,
          sponsor_count,
          community_count
        FROM scored
      )
      INSERT INTO prize_results (
        freeze_id,
        user_id,
        final_score,
        rank,
        stamp_prize,
        rank_prize,
        created_at
      )
      SELECT
        ?1,
        user_id,
        final_score,
        rank,
        CASE WHEN sponsor_count + community_count >= ?4 THEN 1 ELSE 0 END,
        CASE WHEN rank <= ?5 THEN 1 ELSE 0 END,
        ?6
      FROM ranked
      `,
    )
    .bind(
      freezeId,
      SCORE_PER_COLLECTION,
      PHISHING_PENALTY,
      STAMP_THRESHOLD,
      RANK_THRESHOLD,
      nowIso(),
      scoringCutoffAt,
    )
    .run();
}

async function markPhishingEventsApplied(db: D1Database, freezeId: string, scoringCutoffAt: string) {
  await db
    .prepare(
      `
      UPDATE phishing_events
      SET applied_freeze_id = ?1
      WHERE applied_freeze_id IS NULL AND created_at <= ?2
      `,
    )
    .bind(freezeId, scoringCutoffAt)
    .run();
}

async function rollbackFailedFreeze(db: D1Database, freezeId: string) {
  const timestamp = nowIso();
  await db
    .prepare("DELETE FROM prize_results WHERE freeze_id = ?1")
    .bind(freezeId)
    .run();
  await db
    .prepare(
      `
      UPDATE phishing_events
      SET applied_freeze_id = NULL
      WHERE applied_freeze_id = ?1
      `,
    )
    .bind(freezeId)
    .run();
  await rollbackScoreboardFreeze(db, freezeId, timestamp);
}

async function transitionToFrozen(db: D1Database, freezeId: string) {
  const timestamp = nowIso();
  await markScoreboardFrozen(db, freezeId, timestamp);

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
