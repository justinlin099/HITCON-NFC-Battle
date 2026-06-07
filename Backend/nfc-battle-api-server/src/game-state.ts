import type { ScoreboardState } from "./freeze";

export interface GameStateRow {
  state: ScoreboardState;
  freeze_id: string | null;
  freeze_started_at: string | null;
  frozen_at: string | null;
  freeze_timeout_seconds: number;
}

export async function getGameState(db: D1Database) {
  const state = await db
    .prepare(
      `
      SELECT
        state,
        freeze_id,
        freeze_started_at,
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
