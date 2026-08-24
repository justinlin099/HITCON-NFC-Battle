import app from "./index";
import { ScoreboardCoordinator } from "./scoreboard-coordinator";
import type { AppBindings } from "./types";

export { ScoreboardCoordinator };

export default {
  fetch(request, env, ctx) {
    return app.fetch(request, env, ctx);
  },
} satisfies ExportedHandler<AppBindings>;
