import type { GameStateRow } from "./game-state";

const CACHE_VERSION = "1";
const OPEN_TTL_SECONDS = 2;
const FROZEN_TTL_SECONDS = 60;

export interface ScoreboardRanking {
  rank: number;
  user_id: string;
  display_name: string;
  emoji_icon: string;
  score: number;
}

export async function getCachedScoreboardRankings(
  requestUrl: string,
  state: GameStateRow,
  offset: number,
  limit: number,
) {
  const cache = getDefaultCache();
  if (!cache) {
    return null;
  }

  try {
    const response = await cache.match(scoreboardCacheKey(requestUrl, state, offset, limit));
    if (!response) {
      return null;
    }

    const rankings: unknown = await response.json();
    return Array.isArray(rankings) ? rankings as ScoreboardRanking[] : null;
  } catch {
    return null;
  }
}

export async function putCachedScoreboardRankings(
  requestUrl: string,
  state: GameStateRow,
  offset: number,
  limit: number,
  rankings: ScoreboardRanking[],
) {
  const cache = getDefaultCache();
  if (!cache) {
    return;
  }

  const ttl = state.state === "FROZEN" ? FROZEN_TTL_SECONDS : OPEN_TTL_SECONDS;
  const response = new Response(JSON.stringify(rankings), {
    headers: {
      "Cache-Control": `max-age=${ttl}`,
      "Content-Type": "application/json",
    },
  });

  try {
    await cache.put(scoreboardCacheKey(requestUrl, state, offset, limit), response);
  } catch {
    // Cache availability must not affect the scoreboard endpoint.
  }
}

function scoreboardCacheKey(
  requestUrl: string,
  state: GameStateRow,
  offset: number,
  limit: number,
) {
  const url = new URL(requestUrl);
  url.pathname = "/__internal/cache/scoreboard";
  url.search = "";
  url.searchParams.set("v", CACHE_VERSION);
  url.searchParams.set("state", state.state);
  if (state.state === "FROZEN" && state.freeze_id) {
    url.searchParams.set("freeze_id", state.freeze_id);
  }
  url.searchParams.set("offset", String(offset));
  url.searchParams.set("limit", String(limit));
  return new Request(url.toString());
}

function getDefaultCache() {
  return typeof caches === "undefined" ? null : caches.default;
}
