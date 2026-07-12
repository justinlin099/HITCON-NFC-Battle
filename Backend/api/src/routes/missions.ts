import { Hono } from "hono";
import { and, eq, inArray } from "drizzle-orm";
import { requireAuth } from "../middleware/auth";
import { makeDb } from "../db/client";
import { stands, scans } from "../db/schema";
import { ok } from "../lib/errors";
import type { AppEnv } from "../types";

export const missionsRoute = new Hono<AppEnv>();

missionsRoute.use("*", requireAuth);

// Shared helper for both sponsor & community progress endpoints. Safe to
// implement now because the data shape doesn't depend on the open scoring
// decisions — it's just "which stand tags has this user already scanned?".
async function getStandProgress(
  c: Parameters<Parameters<typeof missionsRoute.get>[1]>[0],
  kind: "SPONSOR" | "COMMUNITY",
) {
  const db = makeDb(c.env.DB);
  const sub = c.get("claims").sub;

  const allStands = await db.query.stands.findMany({ where: eq(stands.kind, kind) });

  const scannedTargetKind = kind === "SPONSOR" ? "SPONSOR_STAND" : "COMMUNITY_STAND";
  const standOwnerIds = allStands.map((s) => s.ownerUserId);
  const collected = standOwnerIds.length
    ? await db
        .select({ targetUserId: scans.targetUserId })
        .from(scans)
        .where(
          and(
            eq(scans.scannerUserId, sub),
            eq(scans.targetKind, scannedTargetKind),
            inArray(scans.targetUserId, standOwnerIds),
          ),
        )
    : [];
  const collectedSet = new Set(collected.map((r) => r.targetUserId));

  return {
    stands: allStands.map((s) => ({
      id: s.standId,
      name: s.name,
      status: collectedSet.has(s.ownerUserId) ? "collected" : "pending",
      required_for_prize: s.requiredForPrize,
    })),
    collected_count: collectedSet.size,
    total: allStands.length,
  };
}

// GET /missions/sponsor-stands
missionsRoute.get("/sponsor-stands", async (c) => {
  const p = await getStandProgress(c, "SPONSOR");
  // TODO(prize-threshold): the spec returns a single `required_for_prize`
  // number per response. We currently store it per-stand — confirm with
  // organizers whether the threshold is global or per-stand. See
  // DECISIONS.md "Prize threshold scope".
  return ok(c, {
    collected_count: p.collected_count,
    required_for_prize: p.stands[0]?.required_for_prize ?? 10,
    sponsor_stands: p.stands.map(({ id, name, status }) => ({ id, name, status })),
  });
});

// GET /missions/community-stands
missionsRoute.get("/community-stands", async (c) => {
  const p = await getStandProgress(c, "COMMUNITY");
  return ok(c, {
    collected_count: p.collected_count,
    required_for_prize: p.stands[0]?.required_for_prize ?? 10,
    community_stands: p.stands.map(({ id, name, status }) => ({ id, name, status })),
  });
});
