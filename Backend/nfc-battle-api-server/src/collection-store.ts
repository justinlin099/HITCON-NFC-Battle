interface CollectionRow {
  collected_user_id: string;
}

interface StampCountsRow {
  sponsor_count: number;
  community_count: number;
}

export async function collectUser(db: D1Database, scannerUserId: string, collectedUserId: string) {
  const insertResult = await db
    .prepare(
      `
      INSERT OR IGNORE INTO collections (
        scanner_user_id,
        collected_user_id
      )
      VALUES (?1, ?2)
      `,
    )
    .bind(scannerUserId, collectedUserId)
    .run();

  const firstTimeCollected = insertResult.meta.changes > 0;
  return {
    first_time_collected: firstTimeCollected,
  };
}

export async function collectUserIfNew(
  db: D1Database,
  scannerUserId: string,
  collectedUserId: string,
) {
  const alreadyCollected = await hasCollected(db, scannerUserId, collectedUserId);
  if (alreadyCollected) {
    return {
      first_time_collected: false,
    };
  }

  return collectUser(db, scannerUserId, collectedUserId);
}

export async function hasCollected(
  db: D1Database,
  scannerUserId: string,
  collectedUserId: string,
) {
  const row = await db
    .prepare(
      `
      SELECT 1 AS matched
      FROM collections
      WHERE scanner_user_id = ?1 AND collected_user_id = ?2
      `,
    )
    .bind(scannerUserId, collectedUserId)
    .first<{ matched: number }>();

  return row !== null;
}

export async function getCollection(db: D1Database, userId: string) {
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

export async function getStampCounts(db: D1Database, userId: string) {
  return db
    .prepare(
      `
      SELECT
        SUM(CASE WHEN collected.role = 'SPONSOR' THEN 1 ELSE 0 END) AS sponsor_count,
        SUM(CASE WHEN collected.role = 'COMMUNITY' THEN 1 ELSE 0 END) AS community_count
      FROM collections
      INNER JOIN users AS collected ON collected.user_id = collections.collected_user_id
      WHERE collections.scanner_user_id = ?1
      `,
    )
    .bind(userId)
    .first<StampCountsRow>();
}
