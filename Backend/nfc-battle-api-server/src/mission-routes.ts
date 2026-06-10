import { Hono } from "hono";
import { requireAuth } from "./auth";
import { getStampCounts } from "./collection-store";
import { STAMP_THRESHOLD } from "./game-config";
import { success } from "./responses";
import type { AppEnv } from "./types";
import { lazyInitializeUser } from "./user-store";

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
