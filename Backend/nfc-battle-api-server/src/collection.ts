import { Hono } from "hono";
import { requireAuth } from "./auth";
import { nowIso } from "./ids";
import { hasOnlyKeys, isPlainObject, readJson, requiredString } from "./request";
import { errorResponse, success } from "./responses";
import type { AppEnv } from "./types";
import { getUserRow, lazyInitializeUser, publicFullProfileFromRow } from "./user-store";

interface TagOwnerRow {
  user_id: string;
}

const SCAN_COLLECTION_KEYS = new Set(["user_id", "physical_id"]);

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

  const insertResult = await c.env.DB.prepare(
    `
    INSERT OR IGNORE INTO collections (
      scanner_user_id,
      collected_user_id,
      first_collected_at
    )
    VALUES (?1, ?2, ?3)
    `,
  )
    .bind(authUser.userId, request.user_id, nowIso())
    .run();

  if (insertResult.meta.changes > 0) {
    await c.env.DB.prepare(
      `
      UPDATE users
      SET collection_version = collection_version + 1,
          updated_at = ?2
      WHERE user_id = ?1
      `,
    )
      .bind(authUser.userId, nowIso())
      .run();
  }

  return success(c, {
    collected_user_id: request.user_id,
    first_time_collected: insertResult.meta.changes > 0,
    profile: publicFullProfileFromRow(targetUser),
  });
});

export default collection;

async function getTagOwner(db: D1Database, physicalId: string) {
  return db
    .prepare(
      `
      SELECT user_id
      FROM nfc_tags
      WHERE physical_id = ?1
      `,
    )
    .bind(physicalId)
    .first<TagOwnerRow>();
}

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
