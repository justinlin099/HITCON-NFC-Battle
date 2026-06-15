import { nowIso } from "./ids";

interface CollectionRow {
  collected_user_id: string;
}

interface StampCountsRow {
  sponsor_count: number;
  community_count: number;
}

export async function collectUser(db: D1Database, scannerUserId: string, collectedUserId: string) {
  const timestamp = nowIso();
  const insertResult = await db
    .prepare(
      `
      INSERT OR IGNORE INTO collections (
        scanner_user_id,
        collected_user_id,
        first_collected_at
      )
      VALUES (?1, ?2, ?3)
      `,
    )
    .bind(scannerUserId, collectedUserId, timestamp)
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

export interface CollectionCountRow {
  user_id: string;
  display_name: string;
  emoji_icon: string;
  num_of_collection: number;
}

export async function getLiveCollectionScoreRows(db: D1Database, offset: number, limit: number) {
  const { results } = await db
    .prepare(
      `
      WITH scores AS (
        SELECT
          users.user_id,
          users.display_name,
          users.emoji_icon,
          COUNT(collections.collected_user_id) AS num_of_collection
        FROM users
        LEFT JOIN collections ON collections.scanner_user_id = users.user_id
        GROUP BY users.user_id
      ),
      ranked AS (
        SELECT
          ROW_NUMBER() OVER (
            ORDER BY num_of_collection DESC, user_id ASC
          ) AS rank,
          user_id,
          display_name,
          emoji_icon,
          num_of_collection
        FROM scores
      )
      SELECT
        rank,
        user_id,
        display_name,
        emoji_icon,
        num_of_collection
      FROM ranked
      ORDER BY rank ASC
      LIMIT ?1
      OFFSET ?2
      `,
    )
    .bind(limit, offset)
    .all<CollectionCountRow & { rank: number }>();

  return results;
}
