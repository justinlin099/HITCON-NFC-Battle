import { Hono } from "hono";
import { requireAuth } from "./auth";
import { nowIso } from "./ids";
import { hasOnlyKeys, isPlainObject, readJson } from "./request";
import { errorResponse, success } from "./responses";
import { getGameState } from "./game-state";
import type { AppEnv } from "./types";
import { getFullProfile, getUserRow, lazyInitializeUser, profileFromRow } from "./user-store";

interface PrizeResultRow {
  stamp_prize: number;
  rank_prize: number;
  rank: number | null;
}

interface ProfileUpdate {
  display_name?: string;
  emoji_icon?: string;
  bio?: string;
  pixel_avatar_base64?: string;
}

const PATCHABLE_PROFILE_FIELDS = new Set([
  "display_name",
  "emoji_icon",
  "bio",
  "pixel_avatar_base64",
]);

const users = new Hono<AppEnv>();

users.use("*", requireAuth);

users.get("/me", async (c) => {
  const authUser = c.get("authUser");
  await lazyInitializeUser(c.env.DB, authUser.userId, authUser.role);

  const profile = await getFullProfile(c.env.DB, authUser.userId);
  if (!profile) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  return success(c, profile);
});

users.patch("/me", async (c) => {
  const authUser = c.get("authUser");
  await lazyInitializeUser(c.env.DB, authUser.userId, authUser.role);

  const body = await readJson(c);
  const update = validateProfileUpdate(body);
  if (!update) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  await updateMyProfile(c.env.DB, authUser.userId, update);

  const profile = await getFullProfile(c.env.DB, authUser.userId);
  if (!profile) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  return success(c, profile);
});

users.get("/me/prize", async (c) => {
  const authUser = c.get("authUser");
  const state = await getGameState(c.env.DB);
  if (state.state !== "FROZEN" || !state.freeze_id) {
    return errorResponse(c, 409, "SCOREBOARD_NOT_FROZEN", "Scoreboard is not frozen yet.");
  }

  const result = await getPrizeResult(c.env.DB, state.freeze_id, authUser.userId);

  return success(c, {
    scoreboard_frozen: true,
    stamp_prize: result?.stamp_prize === 1,
    rank_prize: result?.rank_prize === 1,
    rank: result?.rank ?? null,
  });
});

users.get("/:user_id", async (c) => {
  const userId = c.req.param("user_id");
  const physicalId = c.req.query("physical_id");
  const row = await getUserRow(c.env.DB, userId);

  if (!row) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  if (physicalId && row.physical_id === physicalId) {
    return success(c, await profileFromRow(c.env.DB, row));
  }

  return success(c, {
    user_id: row.user_id,
    display_name: row.display_name,
    emoji_icon: row.emoji_icon,
  });
});

export default users;

async function updateMyProfile(db: D1Database, userId: string, update: ProfileUpdate) {
  const current = await getUserRow(db, userId);
  if (!current) {
    return;
  }

  await db
    .prepare(
      `
      UPDATE users
      SET
        display_name = ?2,
        emoji_icon = ?3,
        bio = ?4,
        pixel_avatar_base64 = ?5,
        updated_at = ?6
      WHERE user_id = ?1
      `,
    )
    .bind(
      userId,
      update.display_name ?? current.display_name,
      update.emoji_icon ?? current.emoji_icon,
      update.bio ?? current.bio,
      update.pixel_avatar_base64 ?? current.pixel_avatar_base64,
      nowIso(),
    )
    .run();
}

async function getPrizeResult(db: D1Database, freezeId: string, userId: string) {
  return db
    .prepare(
      `
      SELECT
        stamp_prize,
        rank_prize,
        rank
      FROM prize_results
      WHERE freeze_id = ?1 AND user_id = ?2
      `,
    )
    .bind(freezeId, userId)
    .first<PrizeResultRow>();
}

function validateProfileUpdate(value: unknown): ProfileUpdate | null {
  if (!isPlainObject(value)) {
    return null;
  }

  const keys = Object.keys(value);
  if (!hasOnlyKeys(value, PATCHABLE_PROFILE_FIELDS)) {
    return null;
  }

  const update: ProfileUpdate = {};
  for (const key of keys) {
    const fieldValue = value[key];
    if (typeof fieldValue !== "string") {
      return null;
    }

    if ((key === "display_name" || key === "emoji_icon") && fieldValue.trim() === "") {
      return null;
    }

    update[key as keyof ProfileUpdate] = fieldValue;
  }

  return update;
}
