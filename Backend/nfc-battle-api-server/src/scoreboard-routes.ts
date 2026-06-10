import { Hono } from "hono";
import { requireAuth } from "./auth";
import { getLiveCollectionScoreRows } from "./collection-store";
import { getFrozenScoreboardRows } from "./freeze-snapshot-store";
import { RANK_THRESHOLD } from "./game-config";
import { getGameState, isSameGameStateSnapshot } from "./game-state";
import { calculateScore } from "./scoring";
import { errorResponse, success } from "./responses";
import type { AppEnv } from "./types";
import { lazyInitializeUser } from "./user-store";

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;
const MAX_CONSISTENT_READ_ATTEMPTS = 2;

const scoreboard = new Hono<AppEnv>();

scoreboard.use("*", requireAuth);

scoreboard.get("/", async (c) => {
  const authUser = c.get("authUser");
  await lazyInitializeUser(c.env.DB, authUser.userId, authUser.role);

  const pagination = parsePagination(c.req.query("offset"), c.req.query("limit"));
  if (!pagination) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  for (let attempt = 0; attempt < MAX_CONSISTENT_READ_ATTEMPTS; attempt += 1) {
    const state = await getGameState(c.env.DB);
    if (state.state === "FREEZING") {
      return errorResponse(c, 409, "SCOREBOARD_FREEZING", "Scoreboard is being frozen.");
    }

    const rankings =
      state.state === "FROZEN" && state.freeze_id
        ? await getFrozenRankings(c.env.DB, state.freeze_id, pagination.offset, pagination.limit)
        : await getLiveRankings(c.env.DB, pagination.offset, pagination.limit);

    const latestState = await getGameState(c.env.DB);
    if (!isSameGameStateSnapshot(state, latestState)) {
      continue;
    }

    return success(c, {
      offset: pagination.offset,
      limit: pagination.limit,
      rank_threshold: RANK_THRESHOLD,
      frozen: state.state === "FROZEN",
      freeze_id: state.state === "FROZEN" ? state.freeze_id : null,
      scoring_cutoff_at: state.state === "FROZEN" ? state.scoring_cutoff_at : null,
      rankings,
    });
  }

  return errorResponse(c, 409, "SCOREBOARD_FREEZING", "Scoreboard changed while reading.");
});

export default scoreboard;

async function getLiveRankings(db: D1Database, offset: number, limit: number) {
  const results = await getLiveCollectionScoreRows(db, offset, limit);

  return results.map((item) => ({
    rank: item.rank,
    user_id: item.user_id,
    display_name: item.display_name,
    emoji_icon: item.emoji_icon,
    score: calculateScore(item.num_of_collection),
  }));
}

async function getFrozenRankings(db: D1Database, freezeId: string, offset: number, limit: number) {
  const results = await getFrozenScoreboardRows(db, freezeId, offset, limit);

  return results.map((item) => ({
    rank: item.rank,
    user_id: item.user_id,
    display_name: item.display_name,
    emoji_icon: item.emoji_icon,
    score: item.final_score,
  }));
}

function parsePagination(rawOffset: string | undefined, rawLimit: string | undefined) {
  const offset = rawOffset === undefined ? 0 : Number(rawOffset);
  const limit = rawLimit === undefined ? DEFAULT_LIMIT : Number(rawLimit);

  if (
    !Number.isInteger(offset) ||
    !Number.isInteger(limit) ||
    offset < 0 ||
    limit < 1 ||
    limit > MAX_LIMIT
  ) {
    return null;
  }

  return { offset, limit };
}
