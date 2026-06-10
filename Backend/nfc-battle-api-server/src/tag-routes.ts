import { Hono } from "hono";
import { requireAuth } from "./auth";
import { hasOnlyKeys, isPlainObject, readJson, requiredString } from "./request";
import { errorResponse, successMessage } from "./responses";
import { findTag, findTagByUserId, pairTag } from "./tag-store";
import type { AppEnv } from "./types";
import { lazyInitializeUser } from "./user-store";

const PAIR_TAG_KEYS = new Set(["physical_id"]);

const tags = new Hono<AppEnv>();

tags.use("*", requireAuth);

tags.post("/pair", async (c) => {
  const authUser = c.get("authUser");
  await lazyInitializeUser(c.env.DB, authUser.userId, authUser.role);

  const request = validatePairTagRequest(await readJson(c));
  if (!request) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const existingTag = await findTag(c.env.DB, request.physical_id);
  const existingUserTag = await findTagByUserId(c.env.DB, authUser.userId);
  if (existingTag || existingUserTag) {
    return errorResponse(c, 409, "TAG_ALREADY_PAIRED", "This NFC tag is already paired.");
  }

  await pairTag(c.env.DB, request.physical_id, authUser.userId);

  return successMessage(c, "Tag paired successfully.");
});

export default tags;

function validatePairTagRequest(value: unknown) {
  if (!isPlainObject(value) || !hasOnlyKeys(value, PAIR_TAG_KEYS)) {
    return null;
  }

  const physicalId = requiredString(value, "physical_id");
  if (!physicalId) {
    return null;
  }

  return { physical_id: physicalId };
}
