```txt
npm install
npm run dev
```

Copy local secrets before running the Worker:

```txt
cp .dev.vars.example .dev.vars
```

Use `.dev.vars` only for local Worker runtime secrets such as `JWT_SECRET` and
`STAFF_DANGER_TOKEN`.

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

Replace the staging placeholder `database_id` in
[`wrangler.jsonc`](./wrangler.jsonc), then regenerate types and apply remote
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
npm run wrangler -- d1 execute nfc-battle-api-server-staging --remote --command "DROP TRIGGER IF EXISTS bump_collection_version_after_insert; DROP TABLE IF EXISTS prize_results; DROP TABLE IF EXISTS game_state; DROP TABLE IF EXISTS phishing_events; DROP TABLE IF EXISTS collections; DROP TABLE IF EXISTS nfc_tags; DROP TABLE IF EXISTS users;"
npm run wrangler -- d1 execute nfc-battle-api-server-staging --remote --file ./migrations/0001_initial_schema.sql
```

## Manual Production Deploy

Production uses a separate Worker environment and D1 database. Create the
production D1 database:

```txt
npm run wrangler -- d1 create nfc-battle-api-server
```

Replace the production placeholder `database_id` in
[`wrangler.jsonc`](./wrangler.jsonc), then regenerate types and apply remote
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

Backend pull requests and backend pushes run **Backend CI**. Pushes to `main` that touch the backend also run **Backend Staging Deploy**. The staging workflow runs tests, typecheck, remote staging D1 migrations, syncs staging Worker secrets from GitHub environment secrets, and deploys the staging Worker. Shared staging is not updated from unmerged PR code.

The manual **Backend Deploy** workflow can deploy either `staging` or `production`. It expects these repository-level GitHub Actions secrets:

```txt
CLOUDFLARE_ACCOUNT_ID
CLOUDFLARE_API_TOKEN
```

`CLOUDFLARE_ACCOUNT_ID` can be copied from the Cloudflare dashboard URL for the HITCON Events account. `CLOUDFLARE_API_TOKEN` can be generated from Cloudflare **User API Tokens** using the **Edit Cloudflare Workers** template, then adding account-level D1 edit permission so the workflow can apply remote D1 migrations.

Create GitHub Environments named `staging` and `production`, then add these secrets to each environment. GitHub deploy workflows read these environment secrets and sync them to Cloudflare before deploying:

```txt
JWT_SECRET
STAFF_DANGER_TOKEN
```

Before running it, replace the target environment's placeholder `database_id` in
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
