import { nowIso } from "./ids";
import type { UserRole } from "./types";

export interface UserRow {
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

export async function lazyInitializeUser(db: D1Database, userId: string, role: UserRole) {
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

export async function getFullProfile(db: D1Database, userId: string) {
  const row = await getUserRow(db, userId);
  if (!row) {
    return null;
  }

  return profileFromRow(db, row);
}

export async function getUserRow(db: D1Database, userId: string) {
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

export async function profileFromRow(db: D1Database, row: UserRow) {
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

function defaultDisplayName(userId: string) {
  return `Player_${userId.slice(0, 8) || "new"}`;
}
