import { Hono } from "hono";
import { requireAuth } from "./auth";
import { newId, nowIso } from "./ids";
import { hasOnlyKeys, isPlainObject, readJson, requiredString } from "./request";
import { errorResponse, successMessage } from "./responses";
import type { AppEnv } from "./types";
import { getUserRow, lazyInitializeUser } from "./user-store";

const PHISHING_KEYS = new Set(["victim", "attacker"]);

const collections = new Hono<AppEnv>();

collections.use("*", requireAuth);

collections.post("/phishing", async (c) => {
  const authUser = c.get("authUser");
  await lazyInitializeUser(c.env.DB, authUser.userId, authUser.role);

  const request = validatePhishingRequest(await readJson(c));
  if (!request || request.victim !== authUser.userId || request.victim === request.attacker) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  const attacker = await getUserRow(c.env.DB, request.attacker);
  if (!attacker) {
    return errorResponse(c, 400, "BAD_REQUEST", "Invalid request body or query parameter.");
  }

  await c.env.DB.prepare(
    `
    INSERT INTO phishing_events (
      event_id,
      victim_user_id,
      attacker_user_id,
      created_at
    )
    VALUES (?1, ?2, ?3, ?4)
    `,
  )
    .bind(newId("phishing"), request.victim, request.attacker, nowIso())
    .run();

  return successMessage(c, "Phishing event recorded.");
});

export default collections;

function validatePhishingRequest(value: unknown) {
  if (!isPlainObject(value) || !hasOnlyKeys(value, PHISHING_KEYS)) {
    return null;
  }

  const victim = requiredString(value, "victim");
  const attacker = requiredString(value, "attacker");
  if (!victim || !attacker) {
    return null;
  }

  return { victim, attacker };
}
