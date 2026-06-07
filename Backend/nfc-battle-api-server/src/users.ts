import { Hono } from "hono";
import type { Context } from "hono";
import { requireAuth } from "./auth";
import { nowIso } from "./ids";
import { errorResponse, success } from "./responses";
import type { AppEnv, UserRole } from "./types";

interface UserRow {
  user_id: string;
  display_name: string;
  role: UserRole;
  emoji_icon: string;
  bio: string;
  pixel_avatar_base64: string;
  physical_id: string | null;
}

interface CollectionRow {
  collected_user_id: string;
}

interface ProfileUpdate {
  display_name?: string;
  emoji_icon?: string;
  bio?: string;
  pixel_avatar_base64?: string;
}

const PATCHABLE_PROFILE_FIELDS = new Set([
  "display_name",
  "emoji_icon",
  "bio",
  "pixel_avatar_base64",
]);

const users = new Hono<AppEnv>();

users.use("*", requireAuth);

users.get("/me", async (c) => {
  const authUser = c.get("authUser");
  await lazyInitializeUser(c.env.DB, authUser.userId, authUser.role);

  const profile = await getFullProfile(c.env.DB, authUser.userId);
  if (!profile) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  return success(c, profile);
});

users.patch("/me", async (c) => {
  const authUser = c.get("authUser");
  await lazyInitializeUser(c.env.DB, authUser.userId, authUser.role);

  const body = await readJson(c);
  const update = validateProfileUpdate(body);
  if (!update) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  await updateMyProfile(c.env.DB, authUser.userId, update);

  const profile = await getFullProfile(c.env.DB, authUser.userId);
  if (!profile) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  return success(c, profile);
});

users.get("/:user_id", async (c) => {
  const userId = c.req.param("user_id");
  const physicalId = c.req.query("physical_id");
  const row = await getUserRow(c.env.DB, userId);

  if (!row) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  if (physicalId && row.physical_id === physicalId) {
    return success(c, await profileFromRow(c.env.DB, row));
  }

  return success(c, {
    user_id: row.user_id,
    display_name: row.display_name,
    emoji_icon: row.emoji_icon,
  });
});

export default users;

async function lazyInitializeUser(db: D1Database, userId: string, role: UserRole) {
  const timestamp = nowIso();
  await db
    .prepare(
      `
      INSERT OR IGNORE INTO users (
        user_id,
        display_name,
        role,
        emoji_icon,
        bio,
        pixel_avatar_base64,
        created_at,
        updated_at
      )
      VALUES (?1, ?2, ?3, ?4, '', '', ?5, ?5)
      `,
    )
    .bind(userId, defaultDisplayName(userId), role, "🙂", timestamp)
    .run();
}

async function getFullProfile(db: D1Database, userId: string) {
  const row = await getUserRow(db, userId);
  if (!row) {
    return null;
  }

  return profileFromRow(db, row);
}

async function getUserRow(db: D1Database, userId: string) {
  return db
    .prepare(
      `
      SELECT
        users.user_id,
        users.display_name,
        users.role,
        users.emoji_icon,
        users.bio,
        users.pixel_avatar_base64,
        nfc_tags.physical_id
      FROM users
      LEFT JOIN nfc_tags ON nfc_tags.user_id = users.user_id
      WHERE users.user_id = ?1
      `,
    )
    .bind(userId)
    .first<UserRow>();
}

async function profileFromRow(db: D1Database, row: UserRow) {
  const collection = await getCollection(db, row.user_id);

  return {
    user_id: row.user_id,
    display_name: row.display_name,
    role: row.role,
    emoji_icon: row.emoji_icon,
    bio: row.bio,
    pixel_avatar_base64: row.pixel_avatar_base64,
    physical_id: row.physical_id,
    collection,
  };
}

async function getCollection(db: D1Database, userId: string) {
  const { results } = await db
    .prepare(
      `
      SELECT collected_user_id
      FROM collections
      WHERE scanner_user_id = ?1
      ORDER BY first_collected_at ASC, collected_user_id ASC
      `,
    )
    .bind(userId)
    .all<CollectionRow>();

  return results.map((row) => row.collected_user_id);
}

async function updateMyProfile(db: D1Database, userId: string, update: ProfileUpdate) {
  const current = await getUserRow(db, userId);
  if (!current) {
    return;
  }

  await db
    .prepare(
      `
      UPDATE users
      SET
        display_name = ?2,
        emoji_icon = ?3,
        bio = ?4,
        pixel_avatar_base64 = ?5,
        updated_at = ?6
      WHERE user_id = ?1
      `,
    )
    .bind(
      userId,
      update.display_name ?? current.display_name,
      update.emoji_icon ?? current.emoji_icon,
      update.bio ?? current.bio,
      update.pixel_avatar_base64 ?? current.pixel_avatar_base64,
      nowIso(),
    )
    .run();
}

async function readJson(c: Context<AppEnv>) {
  try {
    return (await c.req.json()) as unknown;
  } catch {
    return null;
  }
}

function validateProfileUpdate(value: unknown): ProfileUpdate | null {
  if (!isPlainObject(value)) {
    return null;
  }

  const keys = Object.keys(value);
  if (keys.some((key) => !PATCHABLE_PROFILE_FIELDS.has(key))) {
    return null;
  }

  const update: ProfileUpdate = {};
  for (const key of keys) {
    const fieldValue = value[key];
    if (typeof fieldValue !== "string") {
      return null;
    }

    if ((key === "display_name" || key === "emoji_icon") && fieldValue.trim() === "") {
      return null;
    }

    update[key as keyof ProfileUpdate] = fieldValue;
  }

  return update;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function defaultDisplayName(userId: string) {
  return `Player_${userId.slice(0, 8) || "new"}`;
}
