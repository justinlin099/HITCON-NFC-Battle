```txt
npm install
npm run dev
```

Copy local secrets before running the Worker:

```txt
cp .dev.vars.example .dev.vars
```

```txt
npm run deploy
```

## Checks

```txt
npm test
npm run typecheck
```

## Local Smoke

Use a workspace-local Wrangler config directory if your environment cannot write
to `~/.config`:

```txt
XDG_CONFIG_HOME="$PWD/.wrangler-config" npx wrangler d1 migrations apply nfc-battle-api-server --local
XDG_CONFIG_HOME="$PWD/.wrangler-config" npm run dev -- --port 8797
```

Then verify the Worker and local D1 binding:

```txt
curl http://127.0.0.1:8797/health
```

## Database

Initial D1 schema lives in [`migrations/0001_initial_schema.sql`](./migrations/0001_initial_schema.sql).
It defines only the stable backbone tables; add new migrations incrementally as
API implementation clarifies more details.

For local development and tests, the placeholder `database_id` in
[`wrangler.jsonc`](./wrangler.jsonc) is enough. Apply migrations to Wrangler's
local D1 database:

```txt
npx wrangler d1 migrations apply nfc-battle-api-server --local
```

Wrangler stores local D1 state under its local state directory, so it is not
committed with the repo.

For deploys, create a real D1 database, replace the placeholder `database_id`,
regenerate types, and apply migrations remotely:

```txt
npx wrangler d1 create nfc-battle-api-server
npm run cf-typegen
npx wrangler d1 migrations apply nfc-battle-api-server --remote
```

## GitHub Deploy

The manual **Backend Deploy** workflow expects these GitHub Actions secrets:

```txt
CLOUDFLARE_ACCOUNT_ID
CLOUDFLARE_API_TOKEN
JWT_SECRET
STAFF_DANGER_TOKEN
```

Before running it, replace the placeholder `database_id` in
[`wrangler.jsonc`](./wrangler.jsonc) with the real D1 database ID. The workflow
runs tests, typecheck, remote D1 migrations, Worker secret sync, and deploy.

[For generating/synchronizing types based on your Worker configuration run](https://developers.cloudflare.com/workers/wrangler/commands/#types):

```txt
npm run cf-typegen
```

Pass the `CloudflareBindings` as generics when instantiating `Hono`:

```ts
// src/index.ts
const app = new Hono<{ Bindings: CloudflareBindings }>()
```
