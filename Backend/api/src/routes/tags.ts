import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { requireAuth } from "../middleware/auth";
import { makeDb } from "../db/client";
import { tags, users, auditLog } from "../db/schema";
import { errorResponse } from "../lib/errors";
import type { AppEnv } from "../types";

export const tagsRoute = new Hono<AppEnv>();

tagsRoute.use("*", requireAuth);

// POST /tags/pair — bind a physical NFC UID to the caller's account.
//
// Conflict semantics:
//   - same UID, same owner   → idempotent success
//   - same UID, other owner  → 409 TAG_ALREADY_IN_USE
//
// TODO(repair-flow): re-binding (lost/broken tag) is staff-only and not
// implemented yet — see DECISIONS.md "Re-pair / unbind flow".
tagsRoute.post("/pair", async (c) => {
  const db = makeDb(c.env.DB);
  const sub = c.get("claims").sub;

  const body = (await c.req.json().catch(() => null)) as { physical_uid?: unknown } | null;
  const physicalUid = body?.physical_uid;
  if (typeof physicalUid !== "string" || physicalUid.length === 0) {
    return errorResponse(c, "VALIDATION_ERROR", "physical_uid is required.");
  }

  // Lazy-create user row so pairing works even before /users/me was called.
  await db.insert(users).values({ userId: sub }).onConflictDoNothing();

  const existing = await db.query.tags.findFirst({
    where: eq(tags.physicalUid, physicalUid),
  });
  if (existing) {
    if (existing.ownerUserId === sub) {
      return c.json({ status: "success", message: "Tag paired successfully." });
    }
    return errorResponse(
      c,
      "TAG_ALREADY_IN_USE",
      "This NFC tag is already bound to another user.",
    );
  }

  await db.insert(tags).values({ physicalUid, ownerUserId: sub });
  await db.insert(auditLog).values({
    actorUserId: sub,
    action: "tag.pair",
    details: { physical_uid: physicalUid },
  });

  return c.json({ status: "success", message: "Tag paired successfully." });
});
