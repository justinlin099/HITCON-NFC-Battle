import { Hono } from "hono";
import { requireAuth } from "./auth";
import {
  PHISHING_PENALTY,
  RANK_THRESHOLD,
  SCORE_PER_COLLECTION,
} from "./game-config";
import { limitUserRequests } from "./rate-limit";
import { errorResponse, success } from "./responses";
import { getScoreboardCoordinator } from "./scoreboard-coordinator-service";
import { getScoreboardPresentations } from "./scoreboard-store";
import type { AppEnv } from "./types";

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;

const scoreboard = new Hono<AppEnv>();

scoreboard.use("*", requireAuth);

scoreboard.get("/", limitUserRequests("SCOREBOARD_READ_RATE_LIMITER", "GET /scoreboard"), async (c) => {
  const pagination = parsePagination(c.req.query("offset"), c.req.query("limit"));
  if (!pagination) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const result = await getScoreboardCoordinator(c.env).readPage(
    pagination.offset,
    pagination.limit,
  );
  if (result.status === "FREEZING") {
    return errorResponse(c, 409, "SCOREBOARD_FREEZING", "Scoreboard is being frozen.");
  }
  if (result.status === "UNAVAILABLE") {
    return scoreboardUnavailable(c);
  }

  const presentations = await getScoreboardPresentations(
    c.env.DB,
    result.entries.map((entry) => entry.user_id),
  );
  const rankings = result.entries.flatMap((entry) => {
    const presentation = presentations.get(entry.user_id);
    return presentation
      ? [{
          rank: entry.rank,
          user_id: entry.user_id,
          display_name: presentation.display_name,
          emoji_icon: presentation.emoji_icon,
          score: entry.score,
          external_prize: presentation.external_prize,
        }]
      : [];
  });

  return success(c, {
    offset: pagination.offset,
    limit: pagination.limit,
    rank_threshold: RANK_THRESHOLD,
    frozen: result.frozen,
    freeze_id: result.freeze_id,
    scoring_cutoff_at: result.scoring_cutoff_at,
    rankings,
  });
});

scoreboard.get("/me", limitUserRequests("MY_SCOREBOARD_READ_RATE_LIMITER", "GET /scoreboard/me"), async (c) => {
  const authUser = c.get("authUser");
  const result = await getScoreboardCoordinator(c.env).readUser(authUser.userId);

  if (result.status === "FREEZING") {
    return errorResponse(c, 409, "SCOREBOARD_FREEZING", "Scoreboard is being frozen.");
  }
  if (result.status === "UNAVAILABLE") {
    return scoreboardUnavailable(c);
  }

  return success(c, {
    rank: result.entry?.rank ?? null,
    score: result.entry?.score ?? null,
    num_of_collection: result.entry?.num_of_collection ?? null,
    num_of_phishing: result.entry?.num_of_phishing ?? null,
    score_per_collection: result.entry?.score_per_collection ?? SCORE_PER_COLLECTION,
    phishing_penalty: result.entry?.phishing_penalty ?? PHISHING_PENALTY,
    frozen: result.frozen,
    freeze_id: result.freeze_id,
    scoring_cutoff_at: result.scoring_cutoff_at,
  });
});

export default scoreboard;

function scoreboardUnavailable(c: Parameters<typeof errorResponse>[0]) {
  return errorResponse(
    c,
    409,
    "SCOREBOARD_READ_INCONSISTENT",
    "Scoreboard data is temporarily unavailable. Please retry.",
  );
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
