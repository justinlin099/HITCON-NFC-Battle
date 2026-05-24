import { sqliteTable, text, integer, index, uniqueIndex } from "drizzle-orm/sqlite-core";
import { sql } from "drizzle-orm";

// -----------------------------------------------------------------------------
// users
//   user_id = JWT `sub`. Lazily created on first authenticated request.
//   user_type / emoji_icon are free-form strings — exact enum to be locked in
//   by App side (see DECISIONS.md "Profile vocabulary").
// -----------------------------------------------------------------------------
export const users = sqliteTable("users", {
  userId: text("user_id").primaryKey(),
  displayName: text("display_name").notNull().default(""),
  userType: text("user_type").notNull().default("UNSET"),
  emojiIcon: text("emoji_icon").notNull().default(""),
  bio: text("bio").notNull().default(""),
  pixelAvatarBase64: text("pixel_avatar_base64").notNull().default(""),
  // Cached aggregate; updated transactionally in scan handler. Scoreboard reads
  // from here to avoid GROUP BY on the hot path.
  score: integer("score").notNull().default(0),
  tagsCollected: integer("tags_collected").notNull().default(0),
  createdAt: integer("created_at", { mode: "timestamp_ms" })
    .notNull()
    .default(sql`(unixepoch() * 1000)`),
  updatedAt: integer("updated_at", { mode: "timestamp_ms" })
    .notNull()
    .default(sql`(unixepoch() * 1000)`),
});

// -----------------------------------------------------------------------------
// tags
//   One row per physical NFC tag. owner_user_id is the bound attendee/stand;
//   stand_id is set iff this tag represents a sponsor/community stand.
//
//   physical_uid is the hardware UID read at pair time — used as the
//   anti-clone reference during /collections/scan.
// -----------------------------------------------------------------------------
export const tags = sqliteTable(
  "tags",
  {
    physicalUid: text("physical_uid").primaryKey(),
    ownerUserId: text("owner_user_id")
      .notNull()
      .references(() => users.userId),
    // null for attendee tags; set for stand tags.
    standId: text("stand_id").references(() => stands.standId),
    pairedAt: integer("paired_at", { mode: "timestamp_ms" })
      .notNull()
      .default(sql`(unixepoch() * 1000)`),
  },
  (t) => ({
    byOwner: index("tags_by_owner").on(t.ownerUserId),
  }),
);

// -----------------------------------------------------------------------------
// stands  (sponsor or community)
//   Each stand has an owner "user" account (so scans against a stand still
//   resolve through the same user_id model) plus stand-specific metadata.
// -----------------------------------------------------------------------------
export const stands = sqliteTable(
  "stands",
  {
    standId: text("stand_id").primaryKey(), // e.g. "sp_01", "cs_01"
    kind: text("kind", { enum: ["SPONSOR", "COMMUNITY"] }).notNull(),
    name: text("name").notNull(),
    message: text("message").notNull().default(""),
    requiredForPrize: integer("required_for_prize").notNull().default(10),
    ownerUserId: text("owner_user_id")
      .notNull()
      .references(() => users.userId),
  },
  (t) => ({
    byKind: index("stands_by_kind").on(t.kind),
  }),
);

// -----------------------------------------------------------------------------
// scans
//   Append-only log of every successful scan. Used for:
//     - dedup / cooldown enforcement (see DECISIONS.md "Score rules")
//     - audit trail for disputes
//     - rebuilding aggregates if needed
//
//   target_kind mirrors stands.kind plus ATTENDEE for peer scans.
// -----------------------------------------------------------------------------
export const scans = sqliteTable(
  "scans",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    scannerUserId: text("scanner_user_id")
      .notNull()
      .references(() => users.userId),
    targetUserId: text("target_user_id")
      .notNull()
      .references(() => users.userId),
    targetKind: text("target_kind", {
      enum: ["ATTENDEE", "SPONSOR_STAND", "COMMUNITY_STAND"],
    }).notNull(),
    physicalUid: text("physical_uid").notNull(),
    scoreDelta: integer("score_delta").notNull().default(0),
    createdAt: integer("created_at", { mode: "timestamp_ms" })
      .notNull()
      .default(sql`(unixepoch() * 1000)`),
  },
  (t) => ({
    // For "have I already scanned this target?" lookups in scan handler.
    uniquePair: uniqueIndex("scans_unique_scanner_target").on(
      t.scannerUserId,
      t.targetUserId,
    ),
    byScanner: index("scans_by_scanner").on(t.scannerUserId),
  }),
);

// -----------------------------------------------------------------------------
// redemptions
//   One row per (user_id, prize_category) — uniqueness prevents double-redeem.
//   prize_category enum mirrors the /staff/redeem API.
// -----------------------------------------------------------------------------
export const redemptions = sqliteTable(
  "redemptions",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    userId: text("user_id")
      .notNull()
      .references(() => users.userId),
    prizeCategory: text("prize_category", {
      enum: ["SPONSOR_STAND", "COMMUNITY_STAND", "SCOREBOARD"],
    }).notNull(),
    redeemedByStaffId: text("redeemed_by_staff_id")
      .notNull()
      .references(() => users.userId),
    redeemedAt: integer("redeemed_at", { mode: "timestamp_ms" })
      .notNull()
      .default(sql`(unixepoch() * 1000)`),
  },
  (t) => ({
    uniquePerCategory: uniqueIndex("redemptions_unique").on(
      t.userId,
      t.prizeCategory,
    ),
  }),
);

// -----------------------------------------------------------------------------
// staff_assignments
//   Maps a staff user to the stand they currently represent. Used when a scan
//   target is a Staff badge rather than a stand card — backend infers the
//   stand from this table. (See DECISIONS.md "Staff↔stand mapping".)
// -----------------------------------------------------------------------------
export const staffAssignments = sqliteTable("staff_assignments", {
  staffUserId: text("staff_user_id")
    .primaryKey()
    .references(() => users.userId),
  standId: text("stand_id")
    .notNull()
    .references(() => stands.standId),
});

// -----------------------------------------------------------------------------
// audit_log
//   Generic event log for sensitive ops (pair, redeem, re-pair, staff actions).
//   Free-form `details` JSON; queryable by actor/action/created_at.
// -----------------------------------------------------------------------------
export const auditLog = sqliteTable(
  "audit_log",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    actorUserId: text("actor_user_id").notNull(),
    action: text("action").notNull(),
    details: text("details", { mode: "json" }).$type<Record<string, unknown>>(),
    createdAt: integer("created_at", { mode: "timestamp_ms" })
      .notNull()
      .default(sql`(unixepoch() * 1000)`),
  },
  (t) => ({
    byActor: index("audit_by_actor").on(t.actorUserId),
    byAction: index("audit_by_action").on(t.action),
  }),
);
