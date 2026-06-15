import { Hono } from "hono";
import { requireAuth } from "./auth";
import { hasOnlyKeys, isPlainObject, readJson, requiredString } from "./request";
import { errorResponse, successMessage } from "./responses";
import { getTagOwner, getUserTag, pairTag } from "./tag-store";
import type { AppEnv } from "./types";
import { getUserRow } from "./user-store";

const PAIR_TAG_KEYS = new Set(["physical_id"]);

const tags = new Hono<AppEnv>();

tags.use("*", requireAuth);

tags.post("/pair", async (c) => {
  const authUser = c.get("authUser");

  const request = validatePairTagRequest(await readJson(c));
  if (!request) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const user = await getUserRow(c.env.DB, authUser.userId);
  if (!user) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  const [tagOwner, userTag] = await Promise.all([
    getTagOwner(c.env.DB, request.physical_id),
    getUserTag(c.env.DB, authUser.userId),
  ]);
  if (tagOwner) {
    return errorResponse(c, 409, "TAG_ALREADY_PAIRED", "This NFC tag is already paired.");
  }

  if (userTag) {
    return errorResponse(c, 409, "TAG_ALREADY_PAIRED", "This NFC tag is already paired.");
  }

  const result = await pairTag(c.env.DB, request.physical_id, authUser.userId);
  if (!result.paired) {
    return errorResponse(c, 409, "TAG_ALREADY_PAIRED", "This NFC tag is already paired.");
  }

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
