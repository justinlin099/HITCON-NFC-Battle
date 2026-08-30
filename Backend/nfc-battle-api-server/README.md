```txt
npm install
npm run dev
```

Copy local secrets before running the Worker:

```txt
cp .dev.vars.example .dev.vars
```

Use `.dev.vars` for local Worker runtime settings such as `JWT_SECRET`,
`STAFF_DANGER_TOKEN`, and `PRINT_CARD_MAX_UPLOAD_BYTES`.

The print-card implementation and API paths are retained, but both paths return
`EVENT_ENDED` before accessing D1 or R2. The `PRINT_CARD_IMAGES` R2 binding
blocks remain commented in [`wrangler.jsonc`](./wrangler.jsonc), preserving the
bucket names without exposing the buckets to the deployed Worker.

## Local Wrangler Auth

Wrangler login state is machine-wide by default. For this repo, use the npm
scripts or `npm run wrangler -- ...` instead of plain `wrangler` or
`npx wrangler`. The wrapper loads repo-local Cloudflare credentials from
`.cloudflare.env` and stores Wrangler auth/config state under `.wrangler-config`.

```txt
cp .cloudflare.env.example .cloudflare.env
```

Set `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` in `.cloudflare.env`.
Do not commit this file.

Check the repo-local Wrangler identity:

```txt
npm run wrangler -- whoami
```

## Checks

```txt
npm test
npm run typecheck
```

`npm test` runs both the Node route suite and a local Workers-runtime suite for
the scoreboard Durable Object, including alarms and persisted-state eviction.

## Scoreboard Coordinator

The `ScoreboardCoordinator` Durable Object is the source of truth for the
published live or frozen score/rank snapshot. While scoring is open, its alarm
targets the interval configured by `SCOREBOARD_REFRESH_SECONDS` (10 seconds in
all current environments). The event is permanently frozen, so the former
once-per-minute cron watchdog is disabled. Attendee scoreboard requests read
the latest stored snapshot and do not recalculate global ranks.

The Durable Object class migration is applied by Worker deployment through
[`wrangler.jsonc`](./wrangler.jsonc); it is separate from the D1 migrations.

## OpenAPI Documentation

Swagger UI is served by each deployed API at `/admin/docs/`:

```txt
https://nfc-battle-api.hitcon2026.online/admin/docs/
https://nfc-battle-staging.hitcon2026.online/admin/docs/
```

The page and OpenAPI schema are public, but they do not bypass endpoint
authentication. Protected requests still require a JWT, staff operations still
require the `STAFF` role, and dangerous operations still require
`STAFF_DANGER_TOKEN`.

The hosted specification uses only the origin from which the page was loaded,
so staging documentation sends requests to staging and production documentation
sends requests to production. Swagger credentials are not persisted.

The documentation assets are generated before `npm run dev` and every deploy.
To rebuild them directly, run:

```txt
npm run docs:build
```

After starting the local Worker, open its `/admin/docs/` path:

```txt
http://127.0.0.1:8787/admin/docs/
```

## Manual Load Test

Manual k6 load-test scenarios live in [`scripts/k6/README.md`](./scripts/k6/README.md).

## Local Smoke

Use a workspace-local Wrangler config directory if your environment cannot write
to `~/.config`:

```txt
npm run wrangler -- d1 migrations apply nfc-battle-api-server --local
npm run dev -- --port 8797
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
npm run wrangler -- d1 migrations apply nfc-battle-api-server --local
```

Wrangler stores local D1 state under its local state directory, so it is not
committed with the repo.

## Manual Staging Deploy

Create the staging D1 database:

```txt
npm run wrangler -- d1 create nfc-battle-api-server-staging
```

When re-enabling print cards in a new staging environment, create the private
R2 bucket and uncomment its staging binding in `wrangler.jsonc`:

```txt
npm run wrangler -- r2 bucket create nfc-battle-print-cards-staging
```

Confirm the staging `database_id` in [`wrangler.jsonc`](./wrangler.jsonc)
matches the ID returned by Wrangler, then regenerate types and apply remote
migrations:

```txt
npm run cf-typegen
npm run db:migrate:staging
```

Set staging runtime secrets in Cloudflare. Store these values in a password
manager because Cloudflare will not show them again after upload.

```txt
npm run wrangler -- secret put JWT_SECRET --env staging
npm run wrangler -- secret put STAFF_DANGER_TOKEN --env staging
```

Deploy staging:

```txt
npm run deploy:staging
```

Smoke test staging:

```txt
curl https://nfc-battle-staging.hitcon2026.online/health
```

## Reset Staging Database

Destructive: this deletes all staging data. Use only when staging data is
disposable, and never run this against production.

This keeps the existing staging D1 database ID, drops the application tables,
then applies the current initial schema directly. Applying the schema with
`d1 execute --file` avoids depending on D1 migration history after the tables
have been dropped.

```txt
npm run wrangler -- d1 execute nfc-battle-api-server-staging --remote --command "DROP TRIGGER IF EXISTS bump_collection_version_after_insert; DROP TABLE IF EXISTS prize_results; DROP TABLE IF EXISTS game_state; DROP TABLE IF EXISTS phishing_events_condensed; DROP TABLE IF EXISTS collections; DROP TABLE IF EXISTS nfc_tags; DROP TABLE IF EXISTS users;"
npm run wrangler -- d1 execute nfc-battle-api-server-staging --remote --file ./migrations/0001_initial_schema.sql
```

## Manual Production Deploy

Production uses a separate Worker environment and D1 database. Create the
production D1 database:

```txt
npm run wrangler -- d1 create nfc-battle-api-server
```

When re-enabling print cards in a new production environment, create the
private R2 bucket and uncomment its production binding in `wrangler.jsonc`:

```txt
npm run wrangler -- r2 bucket create nfc-battle-print-cards
```

Confirm the production `database_id` in [`wrangler.jsonc`](./wrangler.jsonc)
matches the ID returned by Wrangler, then regenerate types and apply remote
migrations:

```txt
npm run cf-typegen
npm run db:migrate:production
```

Set production runtime secrets in Cloudflare:

```txt
npm run wrangler -- secret put JWT_SECRET --env production
npm run wrangler -- secret put STAFF_DANGER_TOKEN --env production
```

Deploy production:

```txt
npm run deploy:production
```

## GitHub Deploy

Backend pull requests and backend pushes run **Backend CI**. Pushes to `main` that touch the backend also run **Backend Staging Deploy**. The staging workflow runs tests, typecheck, remote staging D1 migrations, syncs staging Worker secrets from explicitly named repository secrets, and deploys the staging Worker. Shared staging is not updated from unmerged PR code.

The manual **Backend Deploy** workflow can deploy either `staging` or `production`. It expects these repository-level GitHub Actions secrets:

```txt
CLOUDFLARE_ACCOUNT_ID
CLOUDFLARE_API_TOKEN
STAGING_JWT_SECRET
STAGING_STAFF_DANGER_TOKEN
PRODUCTION_JWT_SECRET
PRODUCTION_STAFF_DANGER_TOKEN
```

`CLOUDFLARE_ACCOUNT_ID` can be copied from the Cloudflare dashboard URL for the HITCON Events account. `CLOUDFLARE_API_TOKEN` can be generated from Cloudflare **User API Tokens** using the **Edit Cloudflare Workers** template, then adding account-level D1 edit permission so the workflow can apply remote D1 migrations.

The Cloudflare credentials are shared by staging and production because both are in the HITCON Events account. The four environment-prefixed secrets must contain distinct staging and production values. The workflows sync them to Cloudflare as the runtime secrets `JWT_SECRET` and `STAFF_DANGER_TOKEN` for the selected Worker environment.

Before running it, confirm the target environment's `database_id` in
[`wrangler.jsonc`](./wrangler.jsonc) matches the remote D1 database. The
workflow runs tests, typecheck, remote D1 migrations, Worker secret sync, and
deploy.

[For generating/synchronizing types based on your Worker configuration run](https://developers.cloudflare.com/workers/wrangler/commands/#types):

```txt
npm run cf-typegen
```

Pass the `CloudflareBindings` as generics when instantiating `Hono`:

```ts
// src/index.ts
const app = new Hono<{ Bindings: CloudflareBindings }>()
```
