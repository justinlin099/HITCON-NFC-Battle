import { Hono } from "hono";
import { requireAuth } from "./auth";
import { hasCollected } from "./collection-store";
import { hasOnlyKeys, isPlainObject, readJson } from "./request";
import { errorResponse, success } from "./responses";
import { getGameState, isSameGameStateSnapshot } from "./game-state";
import { getPrizeResult } from "./freeze-snapshot-store";
import type { AppEnv } from "./types";
import {
  getFullProfile,
  getHydratedCollection,
  getUserRow,
  getUserRowsById,
  getVisibleProfile,
  lazyInitializeUser,
  type ProfileUpdate,
  publicFullProfileFromRow,
  updateUserProfile,
} from "./user-store";

const PATCHABLE_PROFILE_FIELDS = new Set([
  "display_name",
  "emoji_icon",
  "bio",
  "pixel_avatar_base64",
]);
const MAX_CONSISTENT_READ_ATTEMPTS = 2;

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

  await updateUserProfile(c.env.DB, authUser.userId, update);

  const profile = await getFullProfile(c.env.DB, authUser.userId);
  if (!profile) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  return success(c, profile);
});

users.get("/me/prize", async (c) => {
  const authUser = c.get("authUser");

  for (let attempt = 0; attempt < MAX_CONSISTENT_READ_ATTEMPTS; attempt += 1) {
    const state = await getGameState(c.env.DB);
    if (state.state !== "FROZEN" || !state.freeze_id) {
      return errorResponse(c, 409, "SCOREBOARD_NOT_FROZEN", "Scoreboard is not frozen yet.");
    }

    const result = await getPrizeResult(c.env.DB, state.freeze_id, authUser.userId);
    const latestState = await getGameState(c.env.DB);
    if (!isSameGameStateSnapshot(state, latestState)) {
      continue;
    }

    return success(c, {
      scoreboard_frozen: true,
      stamp_prize: result?.stamp_prize === 1,
      rank_prize: result?.rank_prize === 1,
      rank: result?.rank ?? null,
    });
  }

  return errorResponse(
    c,
    409,
    "SCOREBOARD_READ_INCONSISTENT",
    "Scoreboard state changed while reading. Please retry.",
  );
});

users.get("/me/bootstrap", async (c) => {
  const authUser = c.get("authUser");
  await lazyInitializeUser(c.env.DB, authUser.userId, authUser.role);

  const me = await getFullProfile(c.env.DB, authUser.userId);
  if (!me) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  const rowsById = await getUserRowsById(c.env.DB, me.collection);
  const collectedUsers = [];
  for (const collectedUserId of me.collection) {
    const row = rowsById.get(collectedUserId);
    if (row) {
      collectedUsers.push(publicFullProfileFromRow(row));
    }
  }

  return success(c, {
    me,
    collected_users: collectedUsers,
  });
});

users.post("/batch", async (c) => {
  const authUser = c.get("authUser");
  await lazyInitializeUser(c.env.DB, authUser.userId, authUser.role);

  const request = validateBatchGetUsersRequest(await readJson(c));
  if (!request) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const results = [];
  for (const item of request.users) {
    const row = await getUserRow(c.env.DB, item.user_id);
    if (!row) {
      return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
    }

    const canViewFullProfile =
      authUser.userId === row.user_id || (await hasCollected(c.env.DB, authUser.userId, row.user_id));
    if (
      canViewFullProfile &&
      item.profile_version !== undefined &&
      item.collection_version !== undefined &&
      row.profile_version === item.profile_version &&
      row.collection_version === item.collection_version
    ) {
      results.push({
        user_id: row.user_id,
        unchanged: true,
      });
      continue;
    }

    results.push({
      user_id: row.user_id,
      unchanged: false,
      data: getVisibleProfile(row, canViewFullProfile),
    });
  }

  return success(c, { results });
});

users.get("/:user_id", async (c) => {
  const authUser = c.get("authUser");
  const userId = c.req.param("user_id").trim();
  if (userId === "") {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const row = await getUserRow(c.env.DB, userId);

  if (!row) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  const profileVersion = parseOptionalVersion(c.req.query("profile_version"));
  const collectionVersion = parseOptionalVersion(c.req.query("collection_version"));
  if (profileVersion === null || collectionVersion === null) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const canViewFullProfile =
    authUser.userId === row.user_id || (await hasCollected(c.env.DB, authUser.userId, row.user_id));
  if (
    canViewFullProfile &&
    profileVersion !== undefined &&
    collectionVersion !== undefined &&
    row.profile_version === profileVersion &&
    row.collection_version === collectionVersion
  ) {
    return success(c, {
      user_id: row.user_id,
      unchanged: true,
    });
  }

  return success(c, getVisibleProfile(row, canViewFullProfile));
});

users.get("/:user_id/collection", async (c) => {
  const authUser = c.get("authUser");
  const userId = c.req.param("user_id").trim();
  if (userId === "") {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const row = await getUserRow(c.env.DB, userId);

  if (!row) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  if (authUser.userId !== userId && !(await hasCollected(c.env.DB, authUser.userId, userId))) {
    return errorResponse(c, 403, "FORBIDDEN", "Forbidden.");
  }

  const collectionVersion = parseOptionalVersion(c.req.query("collection_version"));
  if (collectionVersion === null) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  if (collectionVersion !== undefined && row.collection_version === collectionVersion) {
    return success(c, {
      user_id: row.user_id,
      unchanged: true,
    });
  }

  return success(c, await getHydratedCollection(c.env.DB, authUser.userId, row));
});

export default users;

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

interface BatchGetUserItem {
  user_id: string;
  profile_version?: number;
  collection_version?: number;
}

const BATCH_GET_USERS_KEYS = new Set(["users"]);
const BATCH_GET_USER_ITEM_KEYS = new Set(["user_id", "profile_version", "collection_version"]);

function validateBatchGetUsersRequest(value: unknown): { users: BatchGetUserItem[] } | null {
  if (!isPlainObject(value) || !hasOnlyKeys(value, BATCH_GET_USERS_KEYS)) {
    return null;
  }

  const usersValue = value.users;
  if (!Array.isArray(usersValue) || usersValue.length < 1 || usersValue.length > 100) {
    return null;
  }

  const users: BatchGetUserItem[] = [];
  for (const item of usersValue) {
    if (!isPlainObject(item) || !hasOnlyKeys(item, BATCH_GET_USER_ITEM_KEYS)) {
      return null;
    }

    const userId = item.user_id;
    if (typeof userId !== "string") {
      return null;
    }

    const trimmedUserId = userId.trim();
    if (trimmedUserId === "") {
      return null;
    }

    const profileVersion = parseOptionalVersionValue(item.profile_version);
    const collectionVersion = parseOptionalVersionValue(item.collection_version);
    if (profileVersion === null || collectionVersion === null) {
      return null;
    }

    users.push({
      user_id: trimmedUserId,
      ...(profileVersion !== undefined ? { profile_version: profileVersion } : {}),
      ...(collectionVersion !== undefined ? { collection_version: collectionVersion } : {}),
    });
  }

  return { users };
}

function parseOptionalVersion(value: string | undefined): number | null | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (!/^\d+$/.test(value)) {
    return null;
  }

  return Number(value);
}

function parseOptionalVersionValue(value: unknown): number | null | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    return null;
  }

  return value;
}
