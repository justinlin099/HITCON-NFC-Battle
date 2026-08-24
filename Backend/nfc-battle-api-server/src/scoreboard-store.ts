import { PHISHING_PENALTY, SCORE_PER_COLLECTION } from "./game-config";

const MAX_PROFILE_BATCH_SIZE = 100;

export interface ScoreboardSnapshotEntry {
  rank: number;
  user_id: string;
  score: number;
  num_of_collection: number;
  num_of_phishing: number;
  score_per_collection: number;
  phishing_penalty: number;
}

export interface ScoreboardSourceCursors {
  users: number;
  collections: number;
  phishing_events: number;
}

export interface LiveScoreboardData {
  entries: ScoreboardSnapshotEntry[];
  cursors: ScoreboardSourceCursors;
}

export interface ScoreboardPresentation {
  user_id: string;
  display_name: string;
  emoji_icon: string;
  external_prize: boolean;
}

interface LiveBaselineRow extends ScoreboardSnapshotEntry {
  users_cursor: number;
  collections_cursor: number;
  phishing_events_cursor: number;
}

interface FrozenScoreRow extends ScoreboardSnapshotEntry {}

interface ScoreboardPresentationRow {
  user_id: string;
  display_name: string;
  emoji_icon: string;
  external_prize: number;
}

export async function getLiveScoreboardBaseline(db: D1Database): Promise<LiveScoreboardData> {
  const { results } = await db
    .prepare(
      `
      WITH collection_counts AS (
        SELECT scanner_user_id AS user_id, COUNT(*) AS num_of_collection
        FROM collections
        GROUP BY scanner_user_id
      ),
      phishing_counts AS (
        SELECT victim_id AS user_id, SUM(count) AS num_of_phishing
        FROM phishing_events_condensed
        GROUP BY victim_id
      ),
      scored AS (
        SELECT
          users.user_id,
          COALESCE(collection_counts.num_of_collection, 0) AS num_of_collection,
          COALESCE(phishing_counts.num_of_phishing, 0) AS num_of_phishing,
          (COALESCE(collection_counts.num_of_collection, 0) * ?1)
            - (COALESCE(phishing_counts.num_of_phishing, 0) * ?2) AS score
        FROM users
        LEFT JOIN collection_counts ON collection_counts.user_id = users.user_id
        LEFT JOIN phishing_counts ON phishing_counts.user_id = users.user_id
      ),
      ranked AS (
        SELECT
          ROW_NUMBER() OVER (ORDER BY score DESC, user_id ASC) AS rank,
          user_id,
          score,
          num_of_collection,
          num_of_phishing
        FROM scored
      ),
      source_cursors AS (
        SELECT
          COALESCE((SELECT MAX(rowid) FROM users), 0) AS users_cursor,
          COALESCE((SELECT MAX(rowid) FROM collections), 0) AS collections_cursor,
          COALESCE((SELECT SUM(count) FROM phishing_events_condensed), 0)
            AS phishing_events_cursor
      )
      SELECT
        ranked.rank,
        ranked.user_id,
        ranked.score,
        ranked.num_of_collection,
        ranked.num_of_phishing,
        ?1 AS score_per_collection,
        ?2 AS phishing_penalty,
        source_cursors.users_cursor,
        source_cursors.collections_cursor,
        source_cursors.phishing_events_cursor
      FROM ranked
      CROSS JOIN source_cursors
      ORDER BY ranked.rank ASC
      `,
    )
    .bind(SCORE_PER_COLLECTION, PHISHING_PENALTY)
    .all<LiveBaselineRow>();

  return {
    entries: results.map(scoreEntryFromRow),
    cursors: results.length === 0
      ? { users: 0, collections: 0, phishing_events: 0 }
      : cursorsFromRow(results[0]),
  };
}

export async function getFrozenScoreboardEntries(
  db: D1Database,
  freezeId: string,
): Promise<ScoreboardSnapshotEntry[]> {
  const { results } = await db
    .prepare(
      `
      SELECT
        rank,
        user_id,
        final_score AS score,
        num_of_collection,
        num_of_phishing,
        score_per_collection,
        phishing_penalty
      FROM prize_results
      WHERE freeze_id = ?1
      ORDER BY rank ASC
      `,
    )
    .bind(freezeId)
    .all<FrozenScoreRow>();

  return results.map(scoreEntryFromRow);
}

export async function getScoreboardPresentations(
  db: D1Database,
  userIds: string[],
): Promise<Map<string, ScoreboardPresentation>> {
  const presentations = new Map<string, ScoreboardPresentation>();

  for (let offset = 0; offset < userIds.length; offset += MAX_PROFILE_BATCH_SIZE) {
    const chunk = userIds.slice(offset, offset + MAX_PROFILE_BATCH_SIZE);
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
          users.emoji_icon,
          CASE WHEN external_prize_claims.user_id IS NULL THEN 0 ELSE 1 END AS external_prize
        FROM users
        LEFT JOIN prize_claims AS external_prize_claims
          ON external_prize_claims.user_id = users.user_id
          AND external_prize_claims.type = 'EXTERNAL'
          AND external_prize_claims.freeze_id = ''
        WHERE users.user_id IN (${placeholders})
        `,
      )
      .bind(...chunk)
      .all<ScoreboardPresentationRow>();

    for (const row of results) {
      presentations.set(row.user_id, {
        user_id: row.user_id,
        display_name: row.display_name,
        emoji_icon: row.emoji_icon,
        external_prize: row.external_prize === 1,
      });
    }
  }

  return presentations;
}

function scoreEntryFromRow(row: ScoreboardSnapshotEntry): ScoreboardSnapshotEntry {
  return {
    rank: row.rank,
    user_id: row.user_id,
    score: row.score,
    num_of_collection: row.num_of_collection,
    num_of_phishing: row.num_of_phishing,
    score_per_collection: row.score_per_collection,
    phishing_penalty: row.phishing_penalty,
  };
}

function cursorsFromRow(row: {
  users_cursor: number;
  collections_cursor: number;
  phishing_events_cursor: number;
}): ScoreboardSourceCursors {
  return {
    users: row.users_cursor,
    collections: row.collections_cursor,
    phishing_events: row.phishing_events_cursor,
  };
}
