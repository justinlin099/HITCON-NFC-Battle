import { nowIso } from "./ids";

interface TagOwnerRow {
  user_id: string;
}

interface UserTagRow {
  physical_id: string;
}

export interface PairUserTagResult {
  paired: boolean;
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

// This intentionally stays server-side. STAFF workflows can inspect a user's
// paired UIDs without exposing them through profile responses.
export async function getUserTags(db: D1Database, userId: string) {
  const { results } = await db
    .prepare(
      `
      SELECT physical_id
      FROM nfc_tags
      WHERE user_id = ?1
      ORDER BY paired_at ASC, physical_id ASC
      `,
    )
    .bind(userId)
    .all<UserTagRow>();

  return results.map((row) => row.physical_id);
}

export async function pairUserTag(
  db: D1Database,
  userId: string,
  physicalId: string,
): Promise<PairUserTagResult> {
  const existingOwner = await getTagOwner(db, physicalId);
  if (existingOwner && existingOwner.user_id !== userId) {
    return {
      paired: false,
      conflict: true,
    };
  }

  if (existingOwner?.user_id === userId) {
    return {
      paired: true,
      conflict: false,
    };
  }

  const timestamp = nowIso();
  let result: D1Result;
  try {
    result = await db
      .prepare(
        `
        INSERT OR IGNORE INTO nfc_tags (physical_id, user_id, paired_at, locked_at)
        VALUES (?1, ?2, ?3, ?3)
        `,
      )
      .bind(physicalId, userId, timestamp)
      .run();
  } catch (error) {
    const ownerAfterFailedWrite = await getTagOwner(db, physicalId);
    if (ownerAfterFailedWrite && ownerAfterFailedWrite.user_id !== userId) {
      return {
        paired: false,
        conflict: true,
      };
    }

    throw error;
  }

  if (result.meta.changes === 0) {
    const ownerAfterIgnoredWrite = await getTagOwner(db, physicalId);
    if (ownerAfterIgnoredWrite && ownerAfterIgnoredWrite.user_id !== userId) {
      return {
        paired: false,
        conflict: true,
      };
    }
  }

  return {
    paired: true,
    conflict: false,
  };
}
