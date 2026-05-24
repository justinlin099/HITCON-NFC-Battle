import { Hono } from "hono";
import { desc } from "drizzle-orm";
import { requireAuth } from "../middleware/auth";
import { makeDb } from "../db/client";
import { users } from "../db/schema";
import { ok } from "../lib/errors";
import type { AppEnv } from "../types";

export const scoreboardRoute = new Hono<AppEnv>();

scoreboardRoute.use("*", requireAuth);

// GET /scoreboard/global?limit=N
//
// Reads the cached `users.score` aggregate — kept fresh by the scan handler
// (when implemented). At ~2k attendees a full table scan is fine; no need to
// pre-materialize until we see actual hot-path metrics.
//
// TODO(scoreboard-cache): wrap in Workers Cache API once scan handler lands,
// to absorb the inevitable "everyone refreshes during prize hour" spike.
// See DECISIONS.md "Scoreboard freshness".
scoreboardRoute.get("/global", async (c) => {
  const db = makeDb(c.env.DB);
  const rawLimit = Number(c.req.query("limit") ?? 50);
  const limit = Math.min(Math.max(Number.isFinite(rawLimit) ? rawLimit : 50, 1), 200);

  const rows = await db
    .select({
      userId: users.userId,
      displayName: users.displayName,
      emojiIcon: users.emojiIcon,
      score: users.score,
    })
    .from(users)
    .orderBy(desc(users.score))
    .limit(limit);

  return ok(c, {
    last_updated: new Date().toISOString(),
    rankings: rows.map((r, i) => ({
      rank: i + 1,
      display_name: r.displayName,
      score: r.score,
      emoji_icon: r.emojiIcon,
    })),
  });
});
