import app from "./index";
import { ScoreboardCoordinator } from "./scoreboard-coordinator";
import { getScoreboardCoordinator } from "./scoreboard-coordinator-service";
import type { AppBindings } from "./types";

export { ScoreboardCoordinator };

export default {
  fetch(request, env, ctx) {
    return app.fetch(request, env, ctx);
  },
  scheduled(_controller, env, ctx) {
    ctx.waitUntil(getScoreboardCoordinator(env).watchdog());
  },
} satisfies ExportedHandler<AppBindings>;
