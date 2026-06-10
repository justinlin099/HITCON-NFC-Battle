import { Hono } from "hono";
import { requireAuth } from "./auth";
import { RANK_THRESHOLD } from "./game-config";
import { getGameState, isSameGameStateSnapshot } from "./game-state";
import { calculateScore } from "./scoring";
import { errorResponse, success } from "./responses";
import type { AppEnv } from "./types";
import { lazyInitializeUser } from "./user-store";

interface ScoreboardRow {
  rank: number;
  user_id: string;
  display_name: string;
  emoji_icon: string;
  num_of_collection: number;
}

interface FrozenScoreboardRow {
  rank: number;
  user_id: string;
  display_name: string;
  emoji_icon: string;
  final_score: number;
}

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
  const { results } = await db
    .prepare(
      `
      WITH scores AS (
        SELECT
          users.user_id,
          users.display_name,
          users.emoji_icon,
          COUNT(collections.collected_user_id) AS num_of_collection
        FROM users
        LEFT JOIN collections ON collections.scanner_user_id = users.user_id
        GROUP BY users.user_id
      ),
      ranked AS (
        SELECT
          ROW_NUMBER() OVER (
            ORDER BY num_of_collection DESC, user_id ASC
          ) AS rank,
          user_id,
          display_name,
          emoji_icon,
          num_of_collection
        FROM scores
      )
      SELECT
        rank,
        user_id,
        display_name,
        emoji_icon,
        num_of_collection
      FROM ranked
      ORDER BY rank ASC
      LIMIT ?1
      OFFSET ?2
      `,
    )
    .bind(limit, offset)
    .all<ScoreboardRow>();

  return results.map((item) => ({
    rank: item.rank,
    user_id: item.user_id,
    display_name: item.display_name,
    emoji_icon: item.emoji_icon,
    score: calculateScore(item.num_of_collection),
  }));
}

async function getFrozenRankings(db: D1Database, freezeId: string, offset: number, limit: number) {
  const { results } = await db
    .prepare(
      `
      SELECT
        prize_results.rank,
        users.user_id,
        users.display_name,
        users.emoji_icon,
        prize_results.final_score
      FROM prize_results
      INNER JOIN users ON users.user_id = prize_results.user_id
      WHERE prize_results.freeze_id = ?1
      ORDER BY prize_results.rank ASC
      LIMIT ?2
      OFFSET ?3
      `,
    )
    .bind(freezeId, limit, offset)
    .all<FrozenScoreboardRow>();

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
