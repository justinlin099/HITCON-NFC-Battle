import { nowIso } from "./ids";
import { getCollection } from "./collection-store";
import type { UserRole } from "./types";

const MAX_USER_ROW_BATCH_SIZE = 100;

export interface UserRow {
  user_id: string;
  display_name: string;
  role: UserRole;
  emoji_icon: string;
  bio: string;
  pixel_avatar_base64: string;
  profile_version: number;
  collection_version: number;
  physical_id: string | null;
}

export interface ProfileUpdate {
  display_name?: string;
  emoji_icon?: string;
  bio?: string;
  pixel_avatar_base64?: string;
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
        users.profile_version,
        users.collection_version,
        nfc_tags.physical_id
      FROM users
      LEFT JOIN nfc_tags ON nfc_tags.user_id = users.user_id
      WHERE users.user_id = ?1
      `,
    )
    .bind(userId)
    .first<UserRow>();
}

export async function getUserRowsById(db: D1Database, userIds: string[]) {
  const rowsById = new Map<string, UserRow>();
  for (let offset = 0; offset < userIds.length; offset += MAX_USER_ROW_BATCH_SIZE) {
    const chunk = userIds.slice(offset, offset + MAX_USER_ROW_BATCH_SIZE);
    if (chunk.length === 0) {
      continue;
    }

    const placeholders = chunk.map((_, index) => `?${index + 1}`).join(", ");
    const { results } = await db
      .prepare(
        `
        SELECT
          users.user_id,
          users.display_name,
          users.role,
          users.emoji_icon,
          users.bio,
          users.pixel_avatar_base64,
          users.profile_version,
          users.collection_version,
          nfc_tags.physical_id
        FROM users
        LEFT JOIN nfc_tags ON nfc_tags.user_id = users.user_id
        WHERE users.user_id IN (${placeholders})
        `,
      )
      .bind(...chunk)
      .all<UserRow>();

    for (const row of results) {
      rowsById.set(row.user_id, row);
    }
  }

  return rowsById;
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
    profile_version: row.profile_version,
    collection_version: row.collection_version,
    physical_id: row.physical_id,
    collection,
  };
}

export function publicFullProfileFromRow(row: UserRow) {
  return {
    user_id: row.user_id,
    display_name: row.display_name,
    role: row.role,
    emoji_icon: row.emoji_icon,
    bio: row.bio,
    pixel_avatar_base64: row.pixel_avatar_base64,
    profile_version: row.profile_version,
    collection_version: row.collection_version,
  };
}

export function partialProfileFromRow(row: UserRow) {
  return {
    user_id: row.user_id,
    display_name: row.display_name,
    emoji_icon: row.emoji_icon,
  };
}

export function getVisibleProfile(row: UserRow, canViewFullProfile: boolean) {
  return canViewFullProfile ? publicFullProfileFromRow(row) : partialProfileFromRow(row);
}

export async function getHydratedCollection(db: D1Database, viewerUserId: string, owner: UserRow) {
  const collection = await getCollection(db, owner.user_id);
  const viewerCollection = new Set(await getCollection(db, viewerUserId));
  const rowsById = await getUserRowsById(db, collection);
  const users = [];

  for (const collectedUserId of collection) {
    const row = rowsById.get(collectedUserId);
    if (row) {
      users.push(
        getVisibleProfile(
          row,
          viewerUserId === row.user_id || viewerCollection.has(row.user_id),
        ),
      );
    }
  }

  return {
    user_id: owner.user_id,
    collection_version: owner.collection_version,
    users,
  };
}

export async function updateUserProfile(db: D1Database, userId: string, update: ProfileUpdate) {
  const current = await getUserRow(db, userId);
  if (!current) {
    return;
  }

  const nextDisplayName = update.display_name ?? current.display_name;
  const nextEmojiIcon = update.emoji_icon ?? current.emoji_icon;
  const nextBio = update.bio ?? current.bio;
  const nextPixelAvatar = update.pixel_avatar_base64 ?? current.pixel_avatar_base64;
  const profileChanged =
    nextDisplayName !== current.display_name ||
    nextEmojiIcon !== current.emoji_icon ||
    nextBio !== current.bio ||
    nextPixelAvatar !== current.pixel_avatar_base64;

  if (!profileChanged) {
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
        profile_version = profile_version + 1,
        updated_at = ?6
      WHERE user_id = ?1
      `,
    )
    .bind(
      userId,
      nextDisplayName,
      nextEmojiIcon,
      nextBio,
      nextPixelAvatar,
      nowIso(),
    )
    .run();
}

function defaultDisplayName(userId: string) {
  return `Player_${userId.slice(0, 8) || "new"}`;
}
