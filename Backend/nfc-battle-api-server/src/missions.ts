import { Hono } from "hono";
import { requireAuth } from "./auth";
import { STAMP_THRESHOLD } from "./game-config";
import { success } from "./responses";
import type { AppEnv } from "./types";
import { lazyInitializeUser } from "./user-store";

interface StampCountsRow {
  sponsor_count: number;
  community_count: number;
}

const missions = new Hono<AppEnv>();

missions.use("*", requireAuth);

missions.get("/stamp", async (c) => {
  const authUser = c.get("authUser");
  await lazyInitializeUser(c.env.DB, authUser.userId, authUser.role);

  const counts = await getStampCounts(c.env.DB, authUser.userId);
  const sponsorCount = counts?.sponsor_count ?? 0;
  const communityCount = counts?.community_count ?? 0;

  return success(c, {
    stamp_threshold: STAMP_THRESHOLD,
    sponsor_count: sponsorCount,
    community_count: communityCount,
    eligible_for_stamp_prize: sponsorCount + communityCount >= STAMP_THRESHOLD,
  });
});

export default missions;

async function getStampCounts(db: D1Database, userId: string) {
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
