import { Hono } from "hono";
import collectionRoutes from "./collection-routes";
import { requireAuth } from "./auth";
import missionRoutes from "./mission-routes";
import { success } from "./responses";
import scoreboardRoutes from "./scoreboard-routes";
import { requireStaffDangerToken } from "./staff";
import staffRoutes from "./staff-routes";
import tagRoutes from "./tag-routes";
import type { AppEnv } from "./types";
import userRoutes from "./user-routes";

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

app.route("/users", userRoutes);
app.route("/tags", tagRoutes);
app.route("/collection", collectionRoutes);
app.route("/missions", missionRoutes);
app.route("/scoreboard", scoreboardRoutes);
app.route("/staff", staffRoutes);

export default app;
