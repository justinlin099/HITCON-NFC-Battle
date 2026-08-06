import { Hono } from "hono";
import { eq, desc } from "drizzle-orm";
import { requireAuth } from "../middleware/auth";
import { makeDb } from "../db/client";
import { users, scans } from "../db/schema";
import { errorResponse, ok, ApiError } from "../lib/errors";
import type { AppEnv } from "../types";

export const usersRoute = new Hono<AppEnv>();

usersRoute.use("*", requireAuth);

// GET /users/me — lazy-create the row on first hit.
usersRoute.get("/me", async (c) => {
  const db = makeDb(c.env.DB);
  const sub = c.get("claims").sub;

  let row = await db.query.users.findFirst({ where: eq(users.userId, sub) });
  if (!row) {
    await db.insert(users).values({ userId: sub }).onConflictDoNothing();
    row = await db.query.users.findFirst({ where: eq(users.userId, sub) });
    if (!row) throw new ApiError("INTERNAL_ERROR", "Failed to create user.");
  }

  return ok(c, {
    user_id: row.userId,
    display_name: row.displayName,
    user_type: row.userType,
    emoji_icon: row.emojiIcon,
    bio: row.bio,
    pixel_avatar_base64: row.pixelAvatarBase64,
    stats: { score: row.score, tags_collected: row.tagsCollected },
  });
});

// PATCH /users/me — partial update; only the listed fields are accepted.
usersRoute.patch("/me", async (c) => {
  const db = makeDb(c.env.DB);
  const sub = c.get("claims").sub;
  const body = (await c.req.json().catch(() => null)) as Record<string, unknown> | null;
  if (!body) return errorResponse(c, "VALIDATION_ERROR", "Body must be JSON.");

  // TODO(profile-vocab): enforce enum / length limits once App locks them down.
  // See DECISIONS.md "Profile vocabulary & limits".
  const patch: Partial<typeof users.$inferInsert> = {
    updatedAt: new Date(),
  };
  if (typeof body.display_name === "string") patch.displayName = body.display_name;
  if (typeof body.user_type === "string") patch.userType = body.user_type;
  if (typeof body.emoji_icon === "string") patch.emojiIcon = body.emoji_icon;
  if (typeof body.bio === "string") patch.bio = body.bio;
  if (typeof body.pixel_avatar_base64 === "string")
    patch.pixelAvatarBase64 = body.pixel_avatar_base64;

  // Ensure the user row exists (same lazy-init contract as GET /users/me).
  await db.insert(users).values({ userId: sub, ...patch }).onConflictDoUpdate({
    target: users.userId,
    set: patch,
  });

  return c.json({ status: "success", message: "Profile updated." });
});

// GET /users/:target_id/collection — public-to-attendees view of who someone
// has scanned. We resolve names via a join on scans.target_user_id → users.
usersRoute.get("/:target_id/collection", async (c) => {
  const db = makeDb(c.env.DB);
  const targetId = c.req.param("target_id");

  const owner = await db.query.users.findFirst({
    where: eq(users.userId, targetId),
    columns: { displayName: true },
  });
  if (!owner) return errorResponse(c, "UID_NOT_FOUND", "User does not exist.");

  // TODO(collection-pagination): add cursor pagination once we know the
  // expected upper bound per attendee. See DECISIONS.md "Collection pagination".
  const rows = await db
    .select({
      userId: scans.targetUserId,
      displayName: users.displayName,
      emojiIcon: users.emojiIcon,
      collectedAt: scans.createdAt,
      targetKind: scans.targetKind,
    })
    .from(scans)
    .innerJoin(users, eq(users.userId, scans.targetUserId))
    .where(eq(scans.scannerUserId, targetId))
    .orderBy(desc(scans.createdAt));

  const attendeeScans = rows.filter((r) => r.targetKind === "ATTENDEE");

  return ok(c, {
    owner_display_name: owner.displayName,
    total_collected: attendeeScans.length,
    collection: attendeeScans.map((r) => ({
      user_id: r.userId,
      display_name: r.displayName,
      emoji_icon: r.emojiIcon,
      collected_at: r.collectedAt.toISOString(),
    })),
  });
});
