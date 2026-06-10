import { nowIso } from "./ids";

export interface TagRow {
  physical_id: string;
  user_id: string;
}

interface TagOwnerRow {
  user_id: string;
}

export async function pairTag(db: D1Database, physicalId: string, userId: string) {
  const timestamp = nowIso();
  await db
    .prepare(
      `
      INSERT INTO nfc_tags (physical_id, user_id, paired_at, locked_at)
      VALUES (?1, ?2, ?3, ?3)
      `,
    )
    .bind(physicalId, userId, timestamp)
    .run();
}

export async function findTag(db: D1Database, physicalId: string) {
  return db
    .prepare(
      `
      SELECT physical_id, user_id
      FROM nfc_tags
      WHERE physical_id = ?1
      `,
    )
    .bind(physicalId)
    .first<TagRow>();
}

export async function findTagByUserId(db: D1Database, userId: string) {
  return db
    .prepare(
      `
      SELECT physical_id, user_id
      FROM nfc_tags
      WHERE user_id = ?1
      `,
    )
    .bind(userId)
    .first<TagRow>();
}

export async function getTagOwner(db: D1Database, physicalId: string) {
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
