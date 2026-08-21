import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

const migrationsPath = join(dirname(fileURLToPath(import.meta.url)), "migrations");

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.test.jsonc" },
      miniflare: {
        bindings: {
          TEST_MIGRATIONS: await readD1Migrations(migrationsPath),
        },
      },
    }),
  ],
  test: {
    include: ["test/worker/**/*.test.ts"],
    setupFiles: ["./test/worker/setup.ts"],
  },
});
