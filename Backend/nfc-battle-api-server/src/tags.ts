import { Hono } from "hono";
import { requireAuth } from "./auth";
import { nowIso } from "./ids";
import { hasOnlyKeys, isPlainObject, readJson, requiredString } from "./request";
import { errorResponse, successMessage } from "./responses";
import type { AppEnv } from "./types";
import { lazyInitializeUser } from "./user-store";

interface ExistingTagRow {
  physical_id: string;
  user_id: string;
}

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

  const timestamp = nowIso();
  await c.env.DB.prepare(
    `
    INSERT INTO nfc_tags (physical_id, user_id, paired_at, locked_at)
    VALUES (?1, ?2, ?3, ?3)
    `,
  )
    .bind(request.physical_id, authUser.userId, timestamp)
    .run();

  return successMessage(c, "Tag paired successfully.");
});

export default tags;

async function findTag(db: D1Database, physicalId: string) {
  return db
    .prepare(
      `
      SELECT physical_id, user_id
      FROM nfc_tags
      WHERE physical_id = ?1
      `,
    )
    .bind(physicalId)
    .first<ExistingTagRow>();
}

async function findTagByUserId(db: D1Database, userId: string) {
  return db
    .prepare(
      `
      SELECT physical_id, user_id
      FROM nfc_tags
      WHERE user_id = ?1
      `,
    )
    .bind(userId)
    .first<ExistingTagRow>();
}

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
