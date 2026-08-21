import { PHISHING_PENALTY, SCORE_PER_COLLECTION } from "./game-config";
import { calculateScore } from "./scoring";

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

type DeltaKind = "META" | "USER" | "COLLECTION" | "PHISHING";

interface LiveDeltaRow {
  sort_order: number;
  kind: DeltaKind;
  user_id: string;
  delta: number;
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
        SELECT victim_user_id AS user_id, COUNT(*) AS num_of_phishing
        FROM phishing_events
        GROUP BY victim_user_id
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
          COALESCE((SELECT MAX(rowid) FROM phishing_events), 0) AS phishing_events_cursor
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

export async function advanceLiveScoreboard(
  db: D1Database,
  previousEntries: ScoreboardSnapshotEntry[],
  previousCursors: ScoreboardSourceCursors,
): Promise<LiveScoreboardData | null> {
  const { results } = await db
    .prepare(
      `
      WITH source_cursors AS (
        SELECT
          COALESCE((SELECT MAX(rowid) FROM users), 0) AS users_cursor,
          COALESCE((SELECT MAX(rowid) FROM collections), 0) AS collections_cursor,
          COALESCE((SELECT MAX(rowid) FROM phishing_events), 0) AS phishing_events_cursor
      ),
      events AS (
        SELECT 1 AS sort_order, 'USER' AS kind, users.user_id, 0 AS delta
        FROM users
        CROSS JOIN source_cursors
        WHERE users.rowid > ?1 AND users.rowid <= source_cursors.users_cursor

        UNION ALL

        SELECT
          2 AS sort_order,
          'COLLECTION' AS kind,
          collections.scanner_user_id AS user_id,
          COUNT(*) AS delta
        FROM collections
        CROSS JOIN source_cursors
        WHERE collections.rowid > ?2 AND collections.rowid <= source_cursors.collections_cursor
        GROUP BY collections.scanner_user_id

        UNION ALL

        SELECT
          3 AS sort_order,
          'PHISHING' AS kind,
          phishing_events.victim_user_id AS user_id,
          COUNT(*) AS delta
        FROM phishing_events
        CROSS JOIN source_cursors
        WHERE phishing_events.rowid > ?3
          AND phishing_events.rowid <= source_cursors.phishing_events_cursor
        GROUP BY phishing_events.victim_user_id
      )
      SELECT
        0 AS sort_order,
        'META' AS kind,
        '' AS user_id,
        0 AS delta,
        source_cursors.users_cursor,
        source_cursors.collections_cursor,
        source_cursors.phishing_events_cursor
      FROM source_cursors

      UNION ALL

      SELECT
        events.sort_order,
        events.kind,
        events.user_id,
        events.delta,
        source_cursors.users_cursor,
        source_cursors.collections_cursor,
        source_cursors.phishing_events_cursor
      FROM events
      CROSS JOIN source_cursors
      ORDER BY sort_order ASC, user_id ASC
      `,
    )
    .bind(previousCursors.users, previousCursors.collections, previousCursors.phishing_events)
    .all<LiveDeltaRow>();

  const metadata = results[0];
  if (!metadata || metadata.kind !== "META") {
    throw new Error("Missing live scoreboard source cursors.");
  }

  const cursors = cursorsFromRow(metadata);
  if (
    cursors.users < previousCursors.users ||
    cursors.collections < previousCursors.collections ||
    cursors.phishing_events < previousCursors.phishing_events
  ) {
    return null;
  }

  const countsByUser = new Map(
    previousEntries.map((entry) => [
      entry.user_id,
      {
        num_of_collection: entry.num_of_collection,
        num_of_phishing: entry.num_of_phishing,
      },
    ]),
  );

  for (const event of results.slice(1)) {
    const counts = countsByUser.get(event.user_id) ?? {
      num_of_collection: 0,
      num_of_phishing: 0,
    };

    if (event.kind === "COLLECTION") {
      counts.num_of_collection += event.delta;
    } else if (event.kind === "PHISHING") {
      counts.num_of_phishing += event.delta;
    }

    countsByUser.set(event.user_id, counts);
  }

  return {
    entries: rankLiveScores(countsByUser),
    cursors,
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

function rankLiveScores(
  countsByUser: Map<string, { num_of_collection: number; num_of_phishing: number }>,
) {
  const entries = Array.from(countsByUser, ([userId, counts]) => ({
    user_id: userId,
    score: calculateScore(counts.num_of_collection, counts.num_of_phishing),
    num_of_collection: counts.num_of_collection,
    num_of_phishing: counts.num_of_phishing,
  }));

  entries.sort((left, right) => {
    if (left.score !== right.score) {
      return right.score - left.score;
    }
    return left.user_id < right.user_id ? -1 : left.user_id > right.user_id ? 1 : 0;
  });

  return entries.map((entry, index) => ({
    rank: index + 1,
    ...entry,
    score_per_collection: SCORE_PER_COLLECTION,
    phishing_penalty: PHISHING_PENALTY,
  }));
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
