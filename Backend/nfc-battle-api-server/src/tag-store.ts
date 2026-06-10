import { nowIso } from "./ids";

interface TagOwnerRow {
  user_id: string;
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
