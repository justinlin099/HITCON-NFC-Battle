import { Hono } from "hono";
import {
  claimPrize,
  EXTERNAL_PRIZE_FREEZE_ID,
  getPrizeClaim,
  getPrizeResult,
  type PrizeClaimType,
} from "./freeze-snapshot-store";
import { isFreezingStale } from "./freeze";
import { RANK_THRESHOLD, STAMP_THRESHOLD } from "./game-config";
import { getStampCounts } from "./collection-store";
import {
  getGameState,
  type GameStateRow,
} from "./game-state";
import { requireAuth } from "./auth";
import { newFreezeId, nowIso } from "./ids";
import {
  hasOnlyKeys,
  isPlainObject,
  readJson,
  requiredPhysicalTagId,
  requiredString,
} from "./request";
import { errorResponse, success, successMessage } from "./responses";
import { getScoreboardCoordinator } from "./scoreboard-coordinator-service";
import { getScoreboardPresentations } from "./scoreboard-store";
import { requireStaffDangerToken, requireStaffRole } from "./staff";
import { getPrintCard } from "./print-card-store";
import type { AppEnv } from "./types";
import { getUserNfcTagKey, getUserRow } from "./user-store";
import { getUserTags, pairUserTag, unpairUserTag } from "./tag-store";

const staffRoutes = new Hono<AppEnv>();
const FREEZE_SCOREBOARD_KEYS = new Set(["scoring_cutoff_at"]);
const USER_TAG_KEYS = new Set(["user_id", "physical_id"]);
const USER_UID_KEYS = new Set(["user_id", "uid"]);
const PRIZE_CLAIM_KEYS = new Set(["user_id", "uid", "type"]);
const SHORT_TOKEN_PATTERN = /^[A-Za-z0-9_-]{8,32}$/;

staffRoutes.use("*", requireAuth, requireStaffRole);

staffRoutes.get("/scoreboard_status", requireStaffDangerToken, async (c) => {
  const state = await getGameState(c.env.DB);

  return success(c, scoreboardStatusData(state));
});

staffRoutes.get("/scoreboard", async (c) => {
  const result = await getScoreboardCoordinator(c.env).readAll();
  if (result.status === "FREEZING") {
    return errorResponse(c, 409, "SCOREBOARD_FREEZING", "Scoreboard is being frozen.");
  }
  if (result.status === "UNAVAILABLE") {
    return errorResponse(
      c,
      409,
      "SCOREBOARD_READ_INCONSISTENT",
      "Scoreboard data is temporarily unavailable. Please retry.",
    );
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
    rank_threshold: RANK_THRESHOLD,
    frozen: result.frozen,
    freeze_id: result.freeze_id,
    scoring_cutoff_at: result.scoring_cutoff_at,
    rankings,
  });
});

staffRoutes.post("/pair_user_tag", async (c) => {
  const request = validateUserTagRequest(await readJson(c));
  if (!request) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const user = await getUserRow(c.env.DB, request.user_id);
  if (!user) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  const result = await pairUserTag(c.env.DB, request.user_id, request.physical_id);
  if (result.conflict) {
    return errorResponse(c, 409, "TAG_ALREADY_PAIRED", "This NFC tag is already paired.");
  }

  return successMessage(c, "User tag paired successfully.");
});

staffRoutes.post("/unpair_user_tag", async (c) => {
  const request = validateUserTagRequest(await readJson(c));
  if (!request) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const user = await getUserRow(c.env.DB, request.user_id);
  if (!user) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  const result = await unpairUserTag(c.env.DB, request.user_id, request.physical_id);
  if (result.mismatch) {
    return errorResponse(c, 403, "PHYSICAL_ID_MISMATCH", "Physical tag ID does not match user ID.");
  }

  return successMessage(c, "User tag unpaired successfully.");
});

staffRoutes.get("/print-cards/:short_token", async (c) => {
  const shortToken = c.req.param("short_token");
  if (!SHORT_TOKEN_PATTERN.test(shortToken)) {
    return errorResponse(c, 404, "PRINT_CARD_NOT_FOUND", "Print-card token not found.");
  }

  const card = await getPrintCard(c.env.DB, shortToken);
  if (!card) {
    return errorResponse(c, 404, "PRINT_CARD_NOT_FOUND", "Print-card token not found.");
  }

  const image = await c.env.PRINT_CARD_IMAGES.get(card.object_key);
  if (!image) {
    return errorResponse(c, 404, "PRINT_CARD_NOT_FOUND", "Print-card token not found.");
  }

  return new Response(image.body, {
    status: 200,
    headers: {
      "Content-Type": image.httpMetadata?.contentType ?? "image/png",
      "Content-Disposition": `attachment; filename="${shortToken}.png"`,
      "Cache-Control": "private, no-store",
    },
  });
});

staffRoutes.post("/prize-claims", async (c) => {
  const request = validatePrizeClaimRequest(await readJson(c));
  if (!request) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const user = await getUserRow(c.env.DB, request.user_id);
  if (!user) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  const userTags = await getUserTags(c.env.DB, request.user_id);
  if (!userTags.includes(request.uid)) {
    return errorResponse(c, 403, "PHYSICAL_ID_MISMATCH", "Physical tag ID does not match user ID.");
  }

  if (request.type === "EXTERNAL") {
    const claimedAt = await claimExternalPrize(
      c.env.DB,
      request.user_id,
      c.get("authUser").userId,
    );
    if (!claimedAt) {
      return errorResponse(c, 409, "PRIZE_ALREADY_CLAIMED", "Prize has already been claimed.");
    }

    return success(c, {
      type: "EXTERNAL",
      freeze_id: null,
      user_id: request.user_id,
      claimed_at: claimedAt,
      claimed_by_user_id: c.get("authUser").userId,
    });
  }

  if (request.type === "STAMP") {
    const counts = await getStampCounts(c.env.DB, request.user_id);
    const stampCount = (counts?.sponsor_count ?? 0) + (counts?.community_count ?? 0);
    if (stampCount < STAMP_THRESHOLD) {
      return errorResponse(c, 409, "PRIZE_NOT_ELIGIBLE", "User is not eligible for a prize.");
    }

    const claimedAt = await claimLivePrize(
      c.env.DB,
      "STAMP",
      request.user_id,
      c.get("authUser").userId,
    );
    if (!claimedAt) {
      return errorResponse(c, 409, "PRIZE_ALREADY_CLAIMED", "Prize has already been claimed.");
    }

    return success(c, {
      type: "STAMP",
      freeze_id: null,
      user_id: request.user_id,
      stamp_prize: true,
      rank_prize: false,
      rank: null,
      claimed_at: claimedAt,
      claimed_by_user_id: c.get("authUser").userId,
    });
  }

  const state = await getGameState(c.env.DB);
  if (state.state !== "FROZEN" || !state.freeze_id) {
    return errorResponse(c, 409, "SCOREBOARD_NOT_FROZEN", "Scoreboard is not frozen yet.");
  }

  const prize = await getPrizeResult(c.env.DB, state.freeze_id, request.user_id);
  if (
    !prize ||
    prize.rank_prize !== 1
  ) {
    return errorResponse(c, 409, "PRIZE_NOT_ELIGIBLE", "User is not eligible for a prize.");
  }

  const claimedAt = nowIso();
  const claimed = await claimPrize(
    c.env.DB,
    request.type,
    state.freeze_id,
    request.user_id,
    c.get("authUser").userId,
    claimedAt,
  );
  if (!claimed) {
    return errorResponse(c, 409, "PRIZE_ALREADY_CLAIMED", "Prize has already been claimed.");
  }

  return success(c, {
    type: request.type,
    freeze_id: state.freeze_id,
    user_id: request.user_id,
    stamp_prize: false,
    rank_prize: true,
    rank: prize.rank,
    claimed_at: claimedAt,
  });
});

staffRoutes.get("/prize-claims/:user_id", async (c) => {
  const userId = c.req.param("user_id");
  const type = parsePrizeClaimType(c.req.query("type"));
  if (!type) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const user = await getUserRow(c.env.DB, userId);
  if (!user) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  const freezeId = await prizeClaimFreezeId(c.env.DB, type);
  if (freezeId === null) {
    return errorResponse(c, 409, "SCOREBOARD_NOT_FROZEN", "Scoreboard is not frozen yet.");
  }

  const claim = await getPrizeClaim(c.env.DB, type, freezeId, userId);
  return success(c, {
    user_id: userId,
    type,
    freeze_id: type === "RANKING" ? freezeId : null,
    claimed: claim !== null,
    claimed_at: claim?.claimed_at ?? null,
    claimed_by_user_id: claim?.claimed_by_user_id ?? null,
  });
});

staffRoutes.post("/nfc-unlock-code", async (c) => {
  const request = validateUserUidRequest(await readJson(c));
  if (!request) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  // In some cases, the uid has been changed on the physical tag, so we cannot check for a match here. We will just return the unlock code if the user exists.
  // const userTags = await getUserTags(c.env.DB, request.user_id);
  // if (!userTags.includes(request.uid)) {
  //   return errorResponse(c, 403, "PHYSICAL_ID_MISMATCH", "Physical tag ID does not match user ID.");
  // }

  const nfcTagKey = await getUserNfcTagKey(c.env.DB, request.user_id);
  if (!nfcTagKey) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  return success(c, {
    user_id: request.user_id,
    uid: request.uid,
    unlock_code: nfcTagKey,
  });
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

  try {
    const result = await getScoreboardCoordinator(c.env).freeze(
      freezeId,
      startedAt,
      scoringCutoffAt,
    );
    if (result.status === "ALREADY_FROZEN") {
      return errorResponse(c, 409, "SCOREBOARD_ALREADY_FROZEN", "Scoreboard is already frozen.");
    }
    if (result.status === "FAILED") {
      const error = new Error(result.message);
      console.error("Failed to freeze scoreboard.", error);
      return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
    }

    return success(c, {
      frozen: true,
      freeze_id: freezeId,
      scoring_cutoff_at: scoringCutoffAt,
      frozen_at: result.frozen_at,
      stamp_threshold: STAMP_THRESHOLD,
      rank_threshold: RANK_THRESHOLD,
    });
  } catch (error) {
    console.error("Failed to freeze scoreboard.", error);
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }
});

staffRoutes.post("/resume_scoreboard", requireStaffDangerToken, async (c) => {
  const result = await getScoreboardCoordinator(c.env).resume();
  if (result.status === "NOT_FROZEN") {
    return errorResponse(c, 409, "SCOREBOARD_NOT_FROZEN", "Scoreboard is not frozen yet.");
  }
  if (result.status === "FAILED") {
    console.error("Failed to resume scoreboard.", new Error(result.message));
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

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

function validateUserTagRequest(value: unknown) {
  if (!isPlainObject(value) || !hasOnlyKeys(value, USER_TAG_KEYS)) {
    return null;
  }

  const userId = requiredString(value, "user_id");
  const physicalId = requiredPhysicalTagId(value, "physical_id");
  if (!userId || !physicalId) {
    return null;
  }

  return {
    user_id: userId,
    physical_id: physicalId,
  };
}

function validateUserUidRequest(value: unknown) {
  if (!isPlainObject(value) || !hasOnlyKeys(value, USER_UID_KEYS)) {
    return null;
  }

  const userId = requiredString(value, "user_id");
  const uid = requiredPhysicalTagId(value, "uid");
  if (!userId || !uid) {
    return null;
  }

  return { user_id: userId, uid };
}

function validatePrizeClaimRequest(value: unknown) {
  if (!isPlainObject(value) || !hasOnlyKeys(value, PRIZE_CLAIM_KEYS)) {
    return null;
  }

  const userId = requiredString(value, "user_id");
  const uid = requiredPhysicalTagId(value, "uid");
  const type = parsePrizeClaimType(value.type);
  if (!userId || !uid || !type) {
    return null;
  }

  return { user_id: userId, uid, type };
}

function parsePrizeClaimType(value: unknown): PrizeClaimType | null {
  return value === "EXTERNAL" || value === "STAMP" || value === "RANKING" ? value : null;
}

async function claimExternalPrize(db: D1Database, userId: string, claimedByUserId: string) {
  return claimLivePrize(db, "EXTERNAL", userId, claimedByUserId);
}

async function claimLivePrize(
  db: D1Database,
  type: "EXTERNAL" | "STAMP",
  userId: string,
  claimedByUserId: string,
) {
  const claimedAt = nowIso();
  const claimed = await claimPrize(
    db,
    type,
    EXTERNAL_PRIZE_FREEZE_ID,
    userId,
    claimedByUserId,
    claimedAt,
  );
  return claimed ? claimedAt : null;
}

async function prizeClaimFreezeId(db: D1Database, type: PrizeClaimType) {
  if (type === "EXTERNAL" || type === "STAMP") {
    return EXTERNAL_PRIZE_FREEZE_ID;
  }

  const state = await getGameState(db);
  return state.state === "FROZEN" && state.freeze_id ? state.freeze_id : null;
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
