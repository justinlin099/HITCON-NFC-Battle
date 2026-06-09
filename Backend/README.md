# HITCON 2026 NFC Tag Game Backend API

The product flow is maintained in [`game-flow.md`](./game-flow.md). Treat that
file as the source of truth for backend behavior.

The machine-readable API contract is maintained in [`openapi.yaml`](./openapi.yaml)
and should be updated to match [`game-flow.md`](./game-flow.md) whenever the flow
changes.

Use Swagger UI to view and explore the API contract:

1. Open <https://editor.swagger.io/>.
2. Import or paste the contents of [`openapi.yaml`](./openapi.yaml).
3. Use the rendered Swagger UI panels to inspect endpoints, schemas, examples,
   authentication, and error responses.

## Flow Summary

Before the conference, the mobile app obtains the user's JWT and calls
`GET /users/me`, which lazily initializes the user's profile. Users can update
their display name, emoji icon, bio, and pixel avatar with `PATCH /users/me`.
The backend verifies JWTs with a shared secret and HMAC. JWTs must contain
`sub`, `exp`, `iss`, `aud`, and `role`; `sub` is the user ID and `role` is used
for fast role lookup without querying the database.

At reception, users scan their assigned NFC tag and call `POST /tags/pair` to
bind their profile to the tag's physical ID. The app also writes
`https://game.hitcon2026.online/b?u={user_id}` to the tag, then locks the tag so
it is read-only and cannot be accidentally overwritten.

During the conference, scanning another tag opens the app, reads both the tag URL
and physical ID, then calls `POST /collection/scan`. The server verifies that the
physical ID belongs to the parsed user ID before adding that user to the
scanner's collection. If a user opens a tag URL without a physical NFC scan, the
app calls `POST /collections/phishing` with `victim` and `attacker` so the server
can record the event and apply the score penalty to the victim after the
scoreboard is frozen.

The current provisional score formula is `score = 10 * num_of_collection`.

Near the end of the conference, staff freeze the scoreboard with
`POST /staff/freeze_scoreboard` using `STAFF_DANGER_TOKEN`. The server then
calculates final scores, stamp prizes, and rank prizes once, stores the result
snapshot, and serves that snapshot from `GET /users/me/prize`. Resume invalidates
the current freeze snapshot and reopens scoring. Staff can inspect the current
scoreboard state with `GET /staff/scoreboard_status`. If a freeze stays in
`FREEZING` longer than the configured `freeze_timeout`, staff can use
`POST /staff/resume_scoreboard` to recover it back to `OPEN`.
