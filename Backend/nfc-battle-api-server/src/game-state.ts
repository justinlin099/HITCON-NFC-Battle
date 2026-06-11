import type { ScoreboardState } from "./freeze";

export interface GameStateRow {
  state: ScoreboardState;
  freeze_id: string | null;
  freeze_started_at: string | null;
  scoring_cutoff_at: string | null;
  frozen_at: string | null;
  freeze_timeout_seconds: number;
}

export function isSameGameStateSnapshot(left: GameStateRow, right: GameStateRow) {
  return (
    left.state === right.state &&
    left.freeze_id === right.freeze_id &&
    left.freeze_started_at === right.freeze_started_at &&
    left.scoring_cutoff_at === right.scoring_cutoff_at &&
    left.frozen_at === right.frozen_at
  );
}

export async function getGameState(db: D1Database) {
  const state = await db
    .prepare(
      `
      SELECT
        state,
        freeze_id,
        freeze_started_at,
        scoring_cutoff_at,
        frozen_at,
        freeze_timeout_seconds
      FROM game_state
      WHERE id = 1
      `,
    )
    .first<GameStateRow>();

  if (!state) {
    throw new Error("Missing game_state singleton row.");
  }

  return state;
}

export async function startScoreboardFreeze(
  db: D1Database,
  freezeId: string,
  startedAt: string,
  scoringCutoffAt: string,
) {
  const transition = await db
    .prepare(
      `
      UPDATE game_state
      SET
        state = 'FREEZING',
        freeze_id = ?1,
        freeze_started_at = ?2,
        scoring_cutoff_at = ?3,
        frozen_at = NULL,
        updated_at = ?2
      WHERE id = 1 AND state = 'OPEN'
      `,
    )
    .bind(freezeId, startedAt, scoringCutoffAt)
    .run();

  return transition.meta.changes > 0;
}

export async function markScoreboardFrozen(db: D1Database, freezeId: string, frozenAt: string) {
  const transition = await db
    .prepare(
      `
      UPDATE game_state
      SET
        state = 'FROZEN',
        frozen_at = ?2,
        updated_at = ?2
      WHERE id = 1 AND state = 'FREEZING' AND freeze_id = ?1
      `,
    )
    .bind(freezeId, frozenAt)
    .run();

  return transition.meta.changes > 0;
}

export async function resetScoreboardToOpen(db: D1Database, updatedAt: string) {
  await db
    .prepare(
      `
      UPDATE game_state
      SET
        state = 'OPEN',
        freeze_id = NULL,
        freeze_started_at = NULL,
        scoring_cutoff_at = NULL,
        frozen_at = NULL,
        updated_at = ?1
      WHERE id = 1
      `,
    )
    .bind(updatedAt)
    .run();
}

export async function markScoreboardResumeInProgress(
  db: D1Database,
  freezeId: string,
  startedAt: string,
) {
  const transition = await db
    .prepare(
      `
      UPDATE game_state
      SET
        state = 'FREEZING',
        freeze_started_at = ?2,
        frozen_at = NULL,
        updated_at = ?2
      WHERE id = 1 AND state = 'FROZEN' AND freeze_id = ?1
      `,
    )
    .bind(freezeId, startedAt)
    .run();

  return transition.meta.changes > 0;
}

export async function rollbackScoreboardFreeze(
  db: D1Database,
  freezeId: string,
  updatedAt: string,
) {
  await db
    .prepare(
      `
      UPDATE game_state
      SET
        state = 'OPEN',
        freeze_id = NULL,
        freeze_started_at = NULL,
        scoring_cutoff_at = NULL,
        frozen_at = NULL,
        updated_at = ?2
      WHERE id = 1 AND state = 'FREEZING' AND freeze_id = ?1
      `,
    )
    .bind(freezeId, updatedAt)
    .run();
}
