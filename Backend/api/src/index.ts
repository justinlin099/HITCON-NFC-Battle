import { Hono } from "hono";
import { logger } from "hono/logger";
import { cors } from "hono/cors";
import { ApiError, errorResponse } from "./lib/errors";
import { usersRoute } from "./routes/users";
import { tagsRoute } from "./routes/tags";
import { collectionsRoute } from "./routes/collections";
import { missionsRoute } from "./routes/missions";
import { scoreboardRoute } from "./routes/scoreboard";
import { staffRoute } from "./routes/staff";
import type { AppEnv } from "./types";

const app = new Hono<AppEnv>();

app.use("*", logger());

// CORS: the production client is the Flutter app (no browser origin), but the
// `/b` landing page might do a fetch in some flows. Keep permissive for now —
// revisit if we add browser-facing flows. See DECISIONS.md "CORS scope".
app.use("/v1/*", cors({ origin: "*", allowMethods: ["GET", "POST", "PATCH"] }));

app.get("/", (c) => c.text("HITCON 2026 NFC Battle API"));
app.get("/healthz", (c) => c.json({ status: "ok" }));

const v1 = new Hono<AppEnv>();
v1.route("/users", usersRoute);
v1.route("/tags", tagsRoute);
v1.route("/collections", collectionsRoute);
v1.route("/missions", missionsRoute);
v1.route("/scoreboard", scoreboardRoute);
v1.route("/staff", staffRoute);
app.route("/v1", v1);

app.onError((err, c) => {
  if (err instanceof ApiError) return errorResponse(c, err.code, err.message);
  console.error("Unhandled error:", err);
  return errorResponse(c, "INTERNAL_ERROR", "Unexpected server error.");
});

app.notFound((c) => errorResponse(c, "UID_NOT_FOUND", "Route not found."));

export default app;
