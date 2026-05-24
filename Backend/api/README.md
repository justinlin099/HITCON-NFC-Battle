# HITCON 2026 NFC Battle — Backend API

Cloudflare Workers + Hono + D1 implementation of the spec in
[`../README.md`](../README.md).

- **Runtime:** Cloudflare Workers (V8 isolates)
- **Framework:** [Hono](https://hono.dev/)
- **DB:** Cloudflare D1 (SQLite) via [Drizzle ORM](https://orm.drizzle.team/)
- **Auth:** JWT verification with [`jose`](https://github.com/panva/jose) against the SSO JWKS endpoint

## Status

| Endpoint | Status |
|---|---|
| `GET  /healthz` | ✅ implemented |
| `GET  /v1/users/me` | ✅ implemented (lazy init) |
| `PATCH /v1/users/me` | ✅ implemented |
| `GET  /v1/users/:id/collection` | ✅ implemented |
| `POST /v1/tags/pair` | ✅ implemented |
| `GET  /v1/missions/sponsor-stands` | ✅ implemented |
| `GET  /v1/missions/community-stands` | ✅ implemented |
| `GET  /v1/scoreboard/global` | ✅ implemented |
| `POST /v1/collections/scan` | ✅ implemented (attendee + stand-card paths) — Staff-as-stand fallback and `ciphertext` field still pending |
| `POST /v1/collections/phishing` | ⛔ stub — blocked by `phishing-trust` |
| `GET  /v1/staff/identify/:nfc_uid` | ⛔ stub — blocked by `scoreboard-prize-rules`, `prize-threshold-scope` |
| `POST /v1/staff/redeem` | ⛔ stub — blocked by `redemption-uniqueness` |

See [DECISIONS.md](DECISIONS.md) for the open questions.

## Layout

```
src/
  index.ts              # Hono app, route mounting, error handler
  types.ts              # Env / Variables typing for Hono
  db/
    schema.ts           # Drizzle table definitions (source of truth)
    client.ts           # makeDb(D1Database) → DrizzleD1Database
  middleware/
    auth.ts             # requireAuth (JWT+JWKS), requireStaff
  lib/
    errors.ts           # ApiError, errorResponse, ok
  routes/
    users.ts            # /v1/users/*
    tags.ts             # /v1/tags/*
    collections.ts      # /v1/collections/* (stubs)
    missions.ts         # /v1/missions/*
    scoreboard.ts       # /v1/scoreboard/*
    staff.ts            # /v1/staff/* (stubs)
migrations/             # Drizzle-generated SQL migrations
wrangler.toml           # Worker + D1 binding config
drizzle.config.ts       # Drizzle Kit config
```

## Local dev — Docker (recommended; no host toolchain needed)

```sh
cd Backend/api
cp .dev.vars.example .dev.vars     # fill in SSO_* values (any non-empty
                                   # strings are fine for boot-only test)

# First run will build the image, install deps, and apply migrations.
UID=$(id -u) GID=$(id -g) docker compose up
# → http://localhost:8787
```

Smoke test the unauthenticated endpoints (no JWT needed):

```sh
curl http://localhost:8787/healthz
# {"status":"ok"}
```

Anything under `/v1/*` requires a valid SSO JWT — see "Testing authenticated
endpoints" below.

Useful commands:

```sh
# Tear down (keeps the named volumes — D1 data + node_modules persist)
docker compose down

# Nuke everything including the local D1 database
docker compose down -v

# Run an arbitrary command in the same env (e.g. regenerate migrations)
docker compose run --rm api pnpm db:generate
```

## Local dev — host toolchain (alternative)

If you'd rather run pnpm/wrangler on the host (Node 22+, pnpm 9+):

```sh
pnpm install
cp .dev.vars.example .dev.vars
pnpm db:generate
pnpm db:migrate:local
pnpm dev    # → http://localhost:8787
```

## Testing authenticated endpoints

### Dev bypass (default in `.dev.vars.example`)

For local development without a real SSO, the auth middleware honours an
escape hatch:

```sh
# in .dev.vars
DEV_BYPASS_AUTH="1"
DEV_BYPASS_SUB="dev_user_001"
DEV_BYPASS_ROLE="ATTENDEE"     # or "STAFF" for /v1/staff/* testing
```

Both conditions must hold for the bypass to fire:

1. `ENVIRONMENT=development` (set in `wrangler.toml [vars]`; **prod sets it
   to `"production"`**, so the bypass is structurally unreachable on deploy).
2. `DEV_BYPASS_AUTH=1`.

When active, the middleware logs `[auth] DEV_BYPASS_AUTH active — sub=… role=…`
on every request and injects `{ sub, role }` as the JWT claims. Real
`Authorization` headers are ignored while it's on.

To simulate two users, edit `DEV_BYPASS_SUB` in `.dev.vars` and run
`docker compose restart` (no rebuild needed).

### Real JWT (when SSO is wired up)

Either point `SSO_JWKS_URL` at a local key-server (e.g. `mkjwk` + `http-server`)
and mint short-lived tokens with `jose`, or wait for the real SSO endpoint
to be available. There is no checked-in mint helper yet.

## Deploy

```sh
# Remote D1
pnpm exec wrangler d1 create hitcon_nfc_battle
# Paste the production database_id into wrangler.toml [env.production].

pnpm db:migrate:remote

# Secrets — never put these in wrangler.toml.
pnpm exec wrangler secret put SSO_JWKS_URL  --env production
pnpm exec wrangler secret put SSO_ISSUER    --env production
pnpm exec wrangler secret put SSO_AUDIENCE  --env production

pnpm exec wrangler deploy --env production
```

The production route is `game.hitcon2026.online/v1/*` (configured in
`wrangler.toml`); the `/b` redirect entry and `/.well-known/*` association
files live in the Pages project under
[`../../App/hitcon_nfc_battle/deeplink-hosting/`](../../App/hitcon_nfc_battle/deeplink-hosting/)
— **not** in this Worker.

## What's intentionally not here yet

- **`POST /collections/scan` & friends** — see [DECISIONS.md](DECISIONS.md). Stubs return `500` with an explanatory message rather than guessing scoring/auth rules.
- **Rate limiting** — Cloudflare's per-zone Rate Limiting Rules will handle this at the edge; not worth duplicating in code.
- **Tests** — once the blocked endpoints land, add Vitest + Miniflare integration tests covering the JWT path and the scan dedup invariant.
- **Pages project for `/b` and `/.well-known`** — separate concern, owned by the App side per the main README.
