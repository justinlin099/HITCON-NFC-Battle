import { Hono, type Context, type Next } from "hono";
import { requireAuth } from "./auth";
import { collectUserIfNew } from "./collection-store";
import { recordPhishingEventUnlessFrozen } from "./freeze-snapshot-store";
import { getGameState } from "./game-state";
import {
  hasOnlyKeys,
  isPlainObject,
  readJson,
  requiredPhysicalTagId,
  requiredString,
} from "./request";
import { limitUserRequests } from "./rate-limit";
import { errorResponse, success, successMessage } from "./responses";
import { getTagOwner } from "./tag-store";
import type { AppEnv } from "./types";
import { getUserRow, publicFullProfileFromRow } from "./user-store";

const SCAN_COLLECTION_KEYS = new Set(["user_id", "physical_id"]);
const PHISHING_KEYS = new Set(["victim", "attacker"]);
const EVENT_ENDED_MESSAGE = "Thank you for participating HITCON 2026! See you next year!";

const collection = new Hono<AppEnv>();

collection.use("*", requireAuth);

collection.post("/scan", limitUserRequests("COLLECTION_SCAN_RATE_LIMITER", "POST /collection/scan"), async (c) => {
  const authUser = c.get("authUser");

  const request = validateScanCollectionRequest(await readJson(c));
  if (!request || request.user_id === authUser.userId) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const [scannerUser, targetUser] = await Promise.all([
    getUserRow(c.env.DB, authUser.userId),
    getUserRow(c.env.DB, request.user_id),
  ]);
  if (!scannerUser || !targetUser) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  const tagOwner = await getTagOwner(c.env.DB, request.physical_id);
  if (tagOwner?.user_id !== request.user_id) {
    return errorResponse(c, 403, "PHYSICAL_ID_MISMATCH", "Physical tag ID does not match user ID.");
  }

  const collectionResult = await collectUserIfNew(c.env.DB, authUser.userId, request.user_id);

  return success(c, {
    collected_user_id: request.user_id,
    first_time_collected: collectionResult.first_time_collected,
    profile: publicFullProfileFromRow(targetUser),
  });
});

collection.post(
  "/phishing",
  rejectPhishingAfterEvent,
  limitUserRequests("PHISHING_RECORD_RATE_LIMITER", "POST /collection/phishing"),
  async (c) => {
    const authUser = c.get("authUser");

    const request = validatePhishingRequest(await readJson(c));
    if (!request || request.victim !== authUser.userId || request.victim === request.attacker) {
      return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
    }

    const [victim, attacker] = await Promise.all([
      getUserRow(c.env.DB, request.victim),
      getUserRow(c.env.DB, request.attacker),
    ]);
    if (!victim) {
      return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
    }

    if (!attacker) {
      return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
    }

    const recorded = await recordPhishingEventUnlessFrozen(
      c.env.DB,
      request.victim,
      request.attacker,
    );
    if (!recorded) {
      return errorResponse(c, 409, "EVENT_ENDED", EVENT_ENDED_MESSAGE);
    }

    return successMessage(c, "Phishing event recorded.");
  },
);

export default collection;

async function rejectPhishingAfterEvent(c: Context<AppEnv>, next: Next) {
  const gameState = await getGameState(c.env.DB);
  if (gameState.state === "FROZEN") {
    return errorResponse(c, 409, "EVENT_ENDED", EVENT_ENDED_MESSAGE);
  }

  await next();
}

function validateScanCollectionRequest(value: unknown) {
  if (!isPlainObject(value) || !hasOnlyKeys(value, SCAN_COLLECTION_KEYS)) {
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

function validatePhishingRequest(value: unknown) {
  if (!isPlainObject(value) || !hasOnlyKeys(value, PHISHING_KEYS)) {
    return null;
  }

  const victim = requiredString(value, "victim");
  const attacker = requiredString(value, "attacker");
  if (!victim || !attacker) {
    return null;
  }

  return { victim, attacker };
}
