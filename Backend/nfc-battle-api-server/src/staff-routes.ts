import { Hono } from "hono";
import {
  claimPrize,
  deletePrizeSnapshot,
  getPrizeResult,
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
import { getPrintCard } from "./print-card-store";
import type { AppEnv } from "./types";
import { getUserNfcTagKey, getUserRow } from "./user-store";
import { getUserTags, pairUserTag, unpairUserTag } from "./tag-store";

const staffRoutes = new Hono<AppEnv>();
const FREEZE_SCOREBOARD_KEYS = new Set(["scoring_cutoff_at"]);
const USER_TAG_KEYS = new Set(["user_id", "physical_id"]);
const USER_UID_KEYS = new Set(["user_id", "uid"]);
const SHORT_TOKEN_PATTERN = /^[A-Za-z0-9_-]{8,32}$/;

staffRoutes.use("*", requireAuth, requireStaffRole);

staffRoutes.get("/scoreboard_status", requireStaffDangerToken, async (c) => {
  const state = await getGameState(c.env.DB);

  return success(c, scoreboardStatusData(state));
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
  const request = validateUserUidRequest(await readJson(c));
  if (!request) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const state = await getGameState(c.env.DB);
  if (state.state !== "FROZEN" || !state.freeze_id) {
    return errorResponse(c, 409, "SCOREBOARD_NOT_FROZEN", "Scoreboard is not frozen yet.");
  }

  const user = await getUserRow(c.env.DB, request.user_id);
  if (!user) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  const userTags = await getUserTags(c.env.DB, request.user_id);
  if (!userTags.includes(request.uid)) {
    return errorResponse(c, 403, "PHYSICAL_ID_MISMATCH", "Physical tag ID does not match user ID.");
  }

  const prize = await getPrizeResult(c.env.DB, state.freeze_id, request.user_id);
  if (!prize || (prize.stamp_prize !== 1 && prize.rank_prize !== 1)) {
    return errorResponse(c, 409, "PRIZE_NOT_ELIGIBLE", "User is not eligible for a prize.");
  }

  const claimedAt = nowIso();
  const claimed = await claimPrize(
    c.env.DB,
    state.freeze_id,
    request.user_id,
    c.get("authUser").userId,
    claimedAt,
  );
  if (!claimed) {
    return errorResponse(c, 409, "PRIZE_ALREADY_CLAIMED", "Prize has already been claimed.");
  }

  return success(c, {
    freeze_id: state.freeze_id,
    user_id: request.user_id,
    stamp_prize: prize.stamp_prize === 1,
    rank_prize: prize.rank_prize === 1,
    rank: prize.rank,
    claimed_at: claimedAt,
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

function validateUserTagRequest(value: unknown) {
  if (!isPlainObject(value) || !hasOnlyKeys(value, USER_TAG_KEYS)) {
    return null;
  }

  const userId = requiredString(value, "user_id");
  const physicalId = requiredString(value, "physical_id");
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
  const uid = requiredString(value, "uid");
  if (!userId || !uid) {
    return null;
  }

  return { user_id: userId, uid };
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
