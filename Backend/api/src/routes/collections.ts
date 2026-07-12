import { Hono } from "hono";
import { and, eq, sql } from "drizzle-orm";
import { requireAuth } from "../middleware/auth";
import { makeDb } from "../db/client";
import { tags, users, stands, scans } from "../db/schema";
import { errorResponse } from "../lib/errors";
import type { AppEnv } from "../types";

export const collectionsRoute = new Hono<AppEnv>();

collectionsRoute.use("*", requireAuth);

// Scoring policy — DECISIONS.md `score-rules` (decided 2026-05-24).
const POINTS_ATTENDEE = 10;
const POINTS_STAND = 20;

// POST /collections/scan
//
// Asymmetric: only the scanner earns points. Same (scanner, target) pair can
// only earn once — second scan returns the data with score_delta = 0.
//
// Anti-clone: the scanned physical UID must match the owner stored at pair
// time; spoofing `target_user_id` while presenting someone else's UID fails
// at step (2).
//
// TODO(stand-identity): Staff-as-stand fallback (scanning a Staff badge at a
//   booth without a stand card) still pending — see DECISIONS.md.
// TODO(ciphertext-payload): attendee response omits `ciphertext` until the
//   field's purpose is decided.
collectionsRoute.post("/scan", async (c) => {
  const db = makeDb(c.env.DB);
  const scannerId = c.get("claims").sub;

  const body = (await c.req.json().catch(() => null)) as
    | { target_user_id?: unknown; scanned_nfc_uid?: unknown }
    | null;
  const targetUserId = body?.target_user_id;
  const scannedUid = body?.scanned_nfc_uid;
  if (typeof targetUserId !== "string" || typeof scannedUid !== "string") {
    return errorResponse(
      c,
      "VALIDATION_ERROR",
      "target_user_id and scanned_nfc_uid are required strings.",
    );
  }

  if (targetUserId === scannerId) {
    return errorResponse(
      c,
      "SECURITY_VERIFICATION_FAILED",
      "Cannot scan your own tag.",
    );
  }

  // (1) Tag must exist.
  const tag = await db.query.tags.findFirst({
    where: eq(tags.physicalUid, scannedUid),
  });
  if (!tag) {
    return errorResponse(c, "UID_NOT_FOUND", "Physical tag is not paired.");
  }

  // (2) UID must belong to the claimed target.
  if (tag.ownerUserId !== targetUserId) {
    return errorResponse(
      c,
      "SECURITY_VERIFICATION_FAILED",
      "UID mismatch or insufficient permissions.",
    );
  }

  // (3) Resolve target kind from the tag's stand binding.
  let stand: typeof stands.$inferSelect | undefined;
  let kind: "ATTENDEE" | "SPONSOR_STAND" | "COMMUNITY_STAND" = "ATTENDEE";
  if (tag.standId) {
    stand = await db.query.stands.findFirst({
      where: eq(stands.standId, tag.standId),
    });
    if (!stand) {
      // Tag references a stand_id that no longer exists — treat as data bug.
      return errorResponse(c, "INTERNAL_ERROR", "Stand record missing for tag.");
    }
    kind = stand.kind === "SPONSOR" ? "SPONSOR_STAND" : "COMMUNITY_STAND";
  }

  // (4) Dedup check. If already scanned, we don't insert and don't award.
  const existing = await db.query.scans.findFirst({
    where: and(
      eq(scans.scannerUserId, scannerId),
      eq(scans.targetUserId, targetUserId),
    ),
  });

  if (!existing) {
    const scoreDelta = kind === "ATTENDEE" ? POINTS_ATTENDEE : POINTS_STAND;
    const tagsCollectedDelta = kind === "ATTENDEE" ? 1 : 0;

    // Ensure the scanner row exists (lazy init parity with /users/me).
    await db.insert(users).values({ userId: scannerId }).onConflictDoNothing();

    await db.batch([
      db.insert(scans).values({
        scannerUserId: scannerId,
        targetUserId,
        targetKind: kind,
        physicalUid: scannedUid,
        scoreDelta,
      }),
      db
        .update(users)
        .set({
          score: sql`${users.score} + ${scoreDelta}`,
          tagsCollected: sql`${users.tagsCollected} + ${tagsCollectedDelta}`,
          updatedAt: new Date(),
        })
        .where(eq(users.userId, scannerId)),
    ]);
  }

  // (5) Build the kind-specific response shape from the spec.
  if (kind === "ATTENDEE") {
    const target = await db.query.users.findFirst({
      where: eq(users.userId, targetUserId),
    });
    if (!target) {
      return errorResponse(c, "UID_NOT_FOUND", "Target user not found.");
    }
    return c.json({
      status: "success",
      type: "ATTENDEE" as const,
      data: {
        target_info: {
          user_type: target.userType,
          emoji_icon: target.emojiIcon,
          total_tags: target.tagsCollected,
        },
        pixel_avatar_base64: target.pixelAvatarBase64,
      },
    });
  }

  // Stand response — re-read current_stamps so the second-scan path also shows
  // accurate progress.
  if (!stand) {
    return errorResponse(c, "INTERNAL_ERROR", "Stand record missing.");
  }
  const standKindFilter = stand.kind;
  const stampsRows = await db
    .select({ count: sql<number>`count(*)` })
    .from(scans)
    .innerJoin(stands, eq(stands.ownerUserId, scans.targetUserId))
    .where(
      and(eq(scans.scannerUserId, scannerId), eq(stands.kind, standKindFilter)),
    );
  const currentStamps = Number(stampsRows[0]?.count ?? 0);

  if (kind === "SPONSOR_STAND") {
    return c.json({
      status: "success",
      type: "SPONSOR_STAND" as const,
      data: {
        sponsor_stand_id: stand.standId,
        sponsor_stand_name: stand.name,
        sponsor_stand_message: stand.message,
        current_stamps: currentStamps,
        required_for_prize: stand.requiredForPrize,
      },
    });
  }
  return c.json({
    status: "success",
    type: "COMMUNITY_STAND" as const,
    data: {
      community_stand_id: stand.standId,
      community_stand_name: stand.name,
      community_stand_message: stand.message,
      current_stamps: currentStamps,
      required_for_prize: stand.requiredForPrize,
    },
  });
});

// POST /collections/phishing
// -----------------------------------------------------------------------------
// BLOCKED — see DECISIONS.md "phishing-trust".
// -----------------------------------------------------------------------------
collectionsRoute.post("/phishing", async (c) => {
  return errorResponse(
    c,
    "INTERNAL_ERROR",
    "Not implemented — pending decision on phishing trust model.",
  );
});
