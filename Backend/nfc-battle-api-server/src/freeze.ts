export type ScoreboardState = "OPEN" | "FREEZING" | "FROZEN";

export function isFreezingStale(
  state: ScoreboardState,
  freezeStartedAt: string | null,
  freezeTimeoutSeconds: number,
  now = new Date(),
) {
  if (state !== "FREEZING" || !freezeStartedAt) {
    return false;
  }

  const startedAtMs = Date.parse(freezeStartedAt);
  if (!Number.isFinite(startedAtMs)) {
    return false;
  }

  return now.getTime() - startedAtMs > freezeTimeoutSeconds * 1000;
}
