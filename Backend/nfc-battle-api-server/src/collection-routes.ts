import { Hono } from "hono";
import { requireAuth } from "./auth";
import { collectUser } from "./collection-store";
import { recordPhishingEvent } from "./freeze-snapshot-store";
import { hasOnlyKeys, isPlainObject, readJson, requiredString } from "./request";
import { errorResponse, success, successMessage } from "./responses";
import { getTagOwner } from "./tag-store";
import type { AppEnv } from "./types";
import { getUserRow, lazyInitializeUser, publicFullProfileFromRow } from "./user-store";

const SCAN_COLLECTION_KEYS = new Set(["user_id", "physical_id"]);
const PHISHING_KEYS = new Set(["victim", "attacker"]);

const collection = new Hono<AppEnv>();

collection.use("*", requireAuth);

collection.post("/scan", async (c) => {
  const authUser = c.get("authUser");
  await lazyInitializeUser(c.env.DB, authUser.userId, authUser.role);

  const request = validateScanCollectionRequest(await readJson(c));
  if (!request || request.user_id === authUser.userId) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const targetUser = await getUserRow(c.env.DB, request.user_id);
  if (!targetUser) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  const tagOwner = await getTagOwner(c.env.DB, request.physical_id);
  if (tagOwner?.user_id !== request.user_id) {
    return errorResponse(c, 403, "PHYSICAL_ID_MISMATCH", "Physical tag ID does not match user ID.");
  }

  const collectionResult = await collectUser(c.env.DB, authUser.userId, request.user_id);

  return success(c, {
    collected_user_id: request.user_id,
    first_time_collected: collectionResult.first_time_collected,
    profile: publicFullProfileFromRow(targetUser),
  });
});

collection.post("/phishing", async (c) => {
  const authUser = c.get("authUser");
  await lazyInitializeUser(c.env.DB, authUser.userId, authUser.role);

  const request = validatePhishingRequest(await readJson(c));
  if (!request || request.victim !== authUser.userId || request.victim === request.attacker) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const attacker = await getUserRow(c.env.DB, request.attacker);
  if (!attacker) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  await recordPhishingEvent(c.env.DB, request.victim, request.attacker);

  return successMessage(c, "Phishing event recorded.");
});

export default collection;

function validateScanCollectionRequest(value: unknown) {
  if (!isPlainObject(value) || !hasOnlyKeys(value, SCAN_COLLECTION_KEYS)) {
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
