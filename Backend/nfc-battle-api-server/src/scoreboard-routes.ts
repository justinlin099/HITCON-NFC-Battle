import { Hono } from "hono";
import { requireAuth } from "./auth";
import {
  getLiveCollectionScoreRows,
  getLiveUserScores,
  type LiveUserScore,
  type LiveUserScores,
} from "./collection-store";
import {
  getFrozenScoreboardRows,
  getPrizeClaimsVersion,
  getPrizeResult,
} from "./freeze-snapshot-store";
import {
  PHISHING_PENALTY,
  RANK_THRESHOLD,
  SCORE_PER_COLLECTION,
} from "./game-config";
import { getGameState, isSameGameStateSnapshot } from "./game-state";
import { limitUserRequests } from "./rate-limit";
import { calculateScore } from "./scoring";
import { errorResponse, success } from "./responses";
import {
  getCachedLiveUserScores,
  getCachedScoreboardRankings,
  putCachedLiveUserScores,
  putCachedScoreboardRankings,
  type ScoreboardRanking,
} from "./scoreboard-cache";
import type { AppEnv } from "./types";

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;
const MAX_CONSISTENT_READ_ATTEMPTS = 2;

const scoreboard = new Hono<AppEnv>();

scoreboard.use("*", requireAuth);

scoreboard.get("/", limitUserRequests("USER_STANDARD_RATE_LIMITER", "GET /scoreboard"), async (c) => {
  const pagination = parsePagination(c.req.query("offset"), c.req.query("limit"));
  if (!pagination) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  for (let attempt = 0; attempt < MAX_CONSISTENT_READ_ATTEMPTS; attempt += 1) {
    const state = await getGameState(c.env.DB);
    if (state.state === "FREEZING") {
      return errorResponse(c, 409, "SCOREBOARD_FREEZING", "Scoreboard is being frozen.");
    }

    const prizeClaimsVersion = await getPrizeClaimsVersion(c.env.DB);

    const cachedRankings = await getCachedScoreboardRankings(
      c.req.url,
      state,
      pagination.offset,
      pagination.limit,
      prizeClaimsVersion,
    );
    const rankings = cachedRankings ?? (
      state.state === "FROZEN" && state.freeze_id
        ? await getFrozenRankings(c.env.DB, state.freeze_id, pagination.offset, pagination.limit)
        : await getLiveRankings(c.env.DB, pagination.offset, pagination.limit)
    );

    const latestState = await getGameState(c.env.DB);
    if (!isSameGameStateSnapshot(state, latestState)) {
      continue;
    }

    if (!cachedRankings) {
      c.executionCtx.waitUntil(
        putCachedScoreboardRankings(
          c.req.url,
          state,
          pagination.offset,
          pagination.limit,
          rankings,
          prizeClaimsVersion,
        ),
      );
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

  return errorResponse(
    c,
    409,
    "SCOREBOARD_READ_INCONSISTENT",
    "Scoreboard state changed while reading. Please retry.",
  );
});

scoreboard.get("/me", limitUserRequests("USER_STANDARD_RATE_LIMITER", "GET /scoreboard/me"), async (c) => {
  const authUser = c.get("authUser");

  for (let attempt = 0; attempt < MAX_CONSISTENT_READ_ATTEMPTS; attempt += 1) {
    const state = await getGameState(c.env.DB);
    if (state.state === "FREEZING") {
      return errorResponse(c, 409, "SCOREBOARD_FREEZING", "Scoreboard is being frozen.");
    }

    let cachedLiveScores: LiveUserScores | null = null;
    let liveScores: LiveUserScores | null = null;
    let scoreDetails: (Omit<LiveUserScore, "rank"> & { rank: number | null }) | null;
    let scorePerCollection = SCORE_PER_COLLECTION;
    let phishingPenalty = PHISHING_PENALTY;
    if (state.state === "FROZEN" && state.freeze_id) {
      const result = await getPrizeResult(c.env.DB, state.freeze_id, authUser.userId);
      scorePerCollection = result?.score_per_collection ?? SCORE_PER_COLLECTION;
      phishingPenalty = result?.phishing_penalty ?? PHISHING_PENALTY;
      scoreDetails = result
        ? {
            rank: result.rank,
            score: result.final_score,
            num_of_collection: result.num_of_collection,
            num_of_phishing: result.num_of_phishing,
          }
        : null;
    } else {
      cachedLiveScores = state.state === "OPEN"
        ? await getCachedLiveUserScores(c.req.url)
        : null;
      liveScores = cachedLiveScores ?? await getLiveUserScores(c.env.DB);
      scoreDetails = Object.prototype.hasOwnProperty.call(liveScores, authUser.userId)
        ? liveScores[authUser.userId]
        : null;
    }

    const latestState = await getGameState(c.env.DB);
    if (!isSameGameStateSnapshot(state, latestState)) {
      continue;
    }

    if (state.state === "OPEN" && cachedLiveScores === null && liveScores !== null) {
      c.executionCtx.waitUntil(putCachedLiveUserScores(c.req.url, liveScores));
    }

    return success(c, {
      rank: scoreDetails?.rank ?? null,
      score: scoreDetails?.score ?? null,
      num_of_collection: scoreDetails?.num_of_collection ?? null,
      num_of_phishing: scoreDetails?.num_of_phishing ?? null,
      score_per_collection: scorePerCollection,
      phishing_penalty: phishingPenalty,
      frozen: state.state === "FROZEN",
      freeze_id: state.state === "FROZEN" ? state.freeze_id : null,
      scoring_cutoff_at: state.state === "FROZEN" ? state.scoring_cutoff_at : null,
    });
  }

  return errorResponse(
    c,
    409,
    "SCOREBOARD_READ_INCONSISTENT",
    "Scoreboard state changed while reading. Please retry.",
  );
});

export default scoreboard;

async function getLiveRankings(
  db: D1Database,
  offset: number,
  limit: number,
): Promise<ScoreboardRanking[]> {
  const results = await getLiveCollectionScoreRows(db, offset, limit);

  return results.map((item) => ({
    rank: item.rank,
    user_id: item.user_id,
    display_name: item.display_name,
    emoji_icon: item.emoji_icon,
    score: calculateScore(item.num_of_collection, item.num_of_phishing),
    external_prize: item.external_prize === 1,
  }));
}

async function getFrozenRankings(
  db: D1Database,
  freezeId: string,
  offset: number,
  limit: number,
): Promise<ScoreboardRanking[]> {
  const results = await getFrozenScoreboardRows(db, freezeId, offset, limit);

  return results.map((item) => ({
    rank: item.rank,
    user_id: item.user_id,
    display_name: item.display_name,
    emoji_icon: item.emoji_icon,
    score: item.final_score,
    external_prize: item.external_prize === 1,
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
