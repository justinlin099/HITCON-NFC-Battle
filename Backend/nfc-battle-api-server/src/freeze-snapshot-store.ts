import {
  PHISHING_PENALTY,
  RANK_THRESHOLD,
  SCORE_PER_COLLECTION,
  STAMP_THRESHOLD,
} from "./game-config";
import { newId, nowIso } from "./ids";

export interface PrizeResultRow {
  stamp_prize: number;
  rank_prize: number;
  rank: number | null;
}

export interface FrozenScoreboardRow {
  rank: number;
  user_id: string;
  display_name: string;
  emoji_icon: string;
  final_score: number;
}

export async function recordPhishingEvent(
  db: D1Database,
  victimUserId: string,
  attackerUserId: string,
) {
  await db
    .prepare(
      `
      INSERT INTO phishing_events (
        event_id,
        victim_user_id,
        attacker_user_id,
        created_at
      )
      VALUES (?1, ?2, ?3, ?4)
      `,
    )
    .bind(newId("phishing"), victimUserId, attackerUserId, nowIso())
    .run();
}

export async function writePrizeSnapshot(
  db: D1Database,
  freezeId: string,
  scoringCutoffAt: string,
) {
  await db
    .prepare(
      `
      WITH collection_counts AS (
        SELECT
          scanner_user_id AS user_id,
          COUNT(*) AS num_of_collection
        FROM collections
        WHERE first_collected_at <= ?7
        GROUP BY scanner_user_id
      ),
      phishing_counts AS (
        SELECT
          victim_user_id AS user_id,
          COUNT(*) AS num_of_phishing
        FROM phishing_events
        WHERE applied_freeze_id IS NULL AND created_at <= ?7
        GROUP BY victim_user_id
      ),
      stamp_counts AS (
        SELECT
          collections.scanner_user_id AS user_id,
          SUM(CASE WHEN collected.role = 'SPONSOR' THEN 1 ELSE 0 END) AS sponsor_count,
          SUM(CASE WHEN collected.role = 'COMMUNITY' THEN 1 ELSE 0 END) AS community_count
        FROM collections
        INNER JOIN users AS collected ON collected.user_id = collections.collected_user_id
        WHERE collections.first_collected_at <= ?7
        GROUP BY collections.scanner_user_id
      ),
      scored AS (
        SELECT
          users.user_id,
          (COALESCE(collection_counts.num_of_collection, 0) * ?2)
            - (COALESCE(phishing_counts.num_of_phishing, 0) * ?3) AS final_score,
          COALESCE(stamp_counts.sponsor_count, 0) AS sponsor_count,
          COALESCE(stamp_counts.community_count, 0) AS community_count
        FROM users
        LEFT JOIN collection_counts ON collection_counts.user_id = users.user_id
        LEFT JOIN phishing_counts ON phishing_counts.user_id = users.user_id
        LEFT JOIN stamp_counts ON stamp_counts.user_id = users.user_id
      ),
      ranked AS (
        SELECT
          ROW_NUMBER() OVER (ORDER BY final_score DESC, user_id ASC) AS rank,
          user_id,
          final_score,
          sponsor_count,
          community_count
        FROM scored
      )
      INSERT INTO prize_results (
        freeze_id,
        user_id,
        final_score,
        rank,
        stamp_prize,
        rank_prize,
        created_at
      )
      SELECT
        ?1,
        user_id,
        final_score,
        rank,
        CASE WHEN sponsor_count + community_count >= ?4 THEN 1 ELSE 0 END,
        CASE WHEN rank <= ?5 THEN 1 ELSE 0 END,
        ?6
      FROM ranked
      `,
    )
    .bind(
      freezeId,
      SCORE_PER_COLLECTION,
      PHISHING_PENALTY,
      STAMP_THRESHOLD,
      RANK_THRESHOLD,
      nowIso(),
      scoringCutoffAt,
    )
    .run();
}

export async function markPhishingEventsApplied(
  db: D1Database,
  freezeId: string,
  scoringCutoffAt: string,
) {
  await db
    .prepare(
      `
      UPDATE phishing_events
      SET applied_freeze_id = ?1
      WHERE applied_freeze_id IS NULL AND created_at <= ?2
      `,
    )
    .bind(freezeId, scoringCutoffAt)
    .run();
}

export async function deletePrizeSnapshot(db: D1Database, freezeId: string) {
  await db
    .prepare("DELETE FROM prize_results WHERE freeze_id = ?1")
    .bind(freezeId)
    .run();
}

export async function unmarkPhishingEventsApplied(db: D1Database, freezeId: string) {
  await db
    .prepare(
      `
      UPDATE phishing_events
      SET applied_freeze_id = NULL
      WHERE applied_freeze_id = ?1
      `,
    )
    .bind(freezeId)
    .run();
}

export async function getPrizeResult(db: D1Database, freezeId: string, userId: string) {
  return db
    .prepare(
      `
      SELECT
        stamp_prize,
        rank_prize,
        rank
      FROM prize_results
      WHERE freeze_id = ?1 AND user_id = ?2
      `,
    )
    .bind(freezeId, userId)
    .first<PrizeResultRow>();
}

export async function getFrozenScoreboardRows(
  db: D1Database,
  freezeId: string,
  offset: number,
  limit: number,
) {
  const { results } = await db
    .prepare(
      `
      SELECT
        prize_results.rank,
        users.user_id,
        users.display_name,
        users.emoji_icon,
        prize_results.final_score
      FROM prize_results
      INNER JOIN users ON users.user_id = prize_results.user_id
      WHERE prize_results.freeze_id = ?1
      ORDER BY prize_results.rank ASC
      LIMIT ?2
      OFFSET ?3
      `,
    )
    .bind(freezeId, limit, offset)
    .all<FrozenScoreboardRow>();

  return results;
}
