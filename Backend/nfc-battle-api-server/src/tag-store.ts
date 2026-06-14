import { nowIso } from "./ids";

interface TagOwnerRow {
  user_id: string;
}

export interface ReplaceUserTagResult {
  replaced: boolean;
  conflict: boolean;
}

export async function pairTag(db: D1Database, physicalId: string, userId: string) {
  const timestamp = nowIso();
  const result = await db
    .prepare(
      `
      INSERT OR IGNORE INTO nfc_tags (physical_id, user_id, paired_at, locked_at)
      VALUES (?1, ?2, ?3, ?3)
      `,
    )
    .bind(physicalId, userId, timestamp)
    .run();

  return {
    paired: result.meta.changes > 0,
  };
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

export async function replaceUserTag(
  db: D1Database,
  userId: string,
  newPhysicalId: string,
): Promise<ReplaceUserTagResult> {
  const existingOwner = await getTagOwner(db, newPhysicalId);
  if (existingOwner && existingOwner.user_id !== userId) {
    return {
      replaced: false,
      conflict: true,
    };
  }

  if (existingOwner?.user_id === userId) {
    return {
      replaced: true,
      conflict: false,
    };
  }

  const timestamp = nowIso();
  const result = await db
    .prepare(
      `
      INSERT INTO nfc_tags (physical_id, user_id, paired_at, locked_at)
      VALUES (?1, ?2, ?3, ?3)
      ON CONFLICT(user_id) DO UPDATE SET
        physical_id = excluded.physical_id,
        paired_at = excluded.paired_at,
        locked_at = excluded.locked_at
      `,
    )
    .bind(newPhysicalId, userId, timestamp)
    .run();

  return {
    replaced: result.meta.changes > 0,
    conflict: false,
  };
}
