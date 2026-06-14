# k6 Load Tests

These scripts are manual load tests for staging. They are not part of `npm test`, and they should not be run against production without an explicit test window and quota budget.

Each file in this directory is one scenario. `lazy-initialization.js` is the first scenario; add more scenario files here as backend load-test coverage grows.

## Deterministic Fixture

Generate the full conference-sized fixture:

```txt
npm run load:fixture:generate
```

The default fixture contains 1000 attendees, 100 staff, 20 sponsors, and 20 community users. It writes generated files under `scripts/k6/fixtures/`, which is ignored by Git:

- `full.json`: manifest for k6 scenarios. Future scenarios should read this file and choose how many users or tags they need.
- `seed-full.sql`: deterministic SQL seed. It deletes only fixture users matching `FIXTURE_USER_PREFIX` before inserting the generated users.

Override counts when you want a smaller fixture:

```txt
ATTENDEES=50 STAFF=5 SPONSORS=2 COMMUNITIES=2 npm run load:fixture:generate
```

The tag IDs in `full.json` are intentionally not inserted into `nfc_tags`. They are available physical IDs for pairing scenarios such as `POST /tags/pair`.

Apply the generated seed locally:

```txt
npm run load:fixture:seed:local
```

Apply the generated seed to staging:

```txt
npm run load:fixture:seed:staging
```

Seed commands mutate the target D1 database. They delete only fixture users matching `FIXTURE_USER_PREFIX`, then insert the generated users. The generated SQL avoids explicit `BEGIN TRANSACTION`/`COMMIT` statements because remote D1 execution rejects transaction statements in uploaded SQL. User inserts are chunked so each SQL statement stays small enough for remote D1 execution. Future k6 scenarios should read `full.json` and use scenario-specific environment variables to decide how many fixture users or tags to exercise.

## Lazy Initialization

`lazy-initialization.js` tests first-time `GET /users/me` traffic. It generates a fresh JWT subject for every iteration, so each request should create one new user row and then return that user's profile.

## Environment File

Copy the example file and fill in staging secrets locally:

```txt
cp scripts/k6/.env.example scripts/k6/.env
```

Run with Docker from `Backend/nfc-battle-api-server`:

```txt
npm run load:k6
```

`scripts/k6/.env` is ignored by Git. Do not commit real `JWT_SECRET` or `STAFF_DANGER_TOKEN` values.

`JWT_SECRET`, `JWT_ISSUER`, and `JWT_AUDIENCE` are required. The script fails during setup if any of them are missing.

The default scenario is:

- 10 new users per second
- 30 seconds
- about 300 newly initialized users total

Equivalent Docker command:

```txt
docker run --rm --env-file scripts/k6/.env -v "$PWD:/work" -w /work grafana/k6 run scripts/k6/lazy-initialization.js
```

If k6 is installed locally, run the local-binary shortcut:

```txt
set -a
source scripts/k6/.env
set +a
npm run load:k6:local
```

Equivalent local direct command:

```txt
k6 run scripts/k6/lazy-initialization.js
```

Useful options:

```txt
BASE_URL="https://nfc-battle-staging.hitcon2026.online" \
JWT_SECRET="<staging JWT_SECRET>" \
JWT_ISSUER="hitcon-2026-staging" \
JWT_AUDIENCE="nfc-battle-api-server-staging" \
RATE=10 \
DURATION=30s \
USER_PREFIX="k6_lazy_20260614_a" \
npm run load:k6
```

`USER_PREFIX` is a stable namespace. `RUN_ID` is appended to generated user IDs; if it is omitted, the script generates a timestamp-based run ID so repeated runs still create fresh users. Set a fixed `RUN_ID` only when you intentionally want a repeatable ID set.

## Database Shape

The number of existing rows can affect performance, but not all tests need the same database shape.

For a pure lazy-initialization baseline, an empty or recently reset staging database is useful. It measures the best-case cost of creating new users without extra table size effects.

For capacity planning, seed staging with realistic data first. `GET /users/me` does primary-key lookups and inserts into `users`, so a larger `users` table can add index/page-cache overhead. This endpoint does not scan all users, so row count should usually matter much less than endpoints that aggregate or hydrate large collections, but realistic data is still the better signal before an event.

This test writes new rows. Reset staging after the run if the generated users should not stay in the database.
