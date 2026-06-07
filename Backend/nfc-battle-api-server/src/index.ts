import { Hono } from "hono";
import collection from "./collection";
import { requireAuth } from "./auth";
import { success } from "./responses";
import { requireStaffDangerToken } from "./staff";
import tags from "./tags";
import type { AppEnv } from "./types";
import users from "./users";

const app = new Hono<AppEnv>();

app.get("/health", (c) => {
  return success(c, {
    ok: true,
    database: Boolean(c.env.DB),
  });
});

app.get("/health/auth", requireAuth, (c) => {
  return success(c, {
    user: c.get("authUser"),
  });
});

app.get("/health/staff", requireStaffDangerToken, (c) => {
  return success(c, {
    ok: true,
  });
});

app.route("/users", users);
app.route("/tags", tags);
app.route("/collection", collection);

export default app;
