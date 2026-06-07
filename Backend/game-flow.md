# Game Flow

A valid value for user's role:
* attendee (`ATTENDEE`)
* staff (`STAFF`)
* sponsor (`SPONSOR`)
* community (`COMMUNITY`)

A user's data contains:
* user ID (the hashed KKTIX user ID)
* display name
* user role
* emoji icon
* bio
* pixel_avatar_base64
* NFC tag's physical ID
* collection (other user's ID that the user has previously scanned)

The `stamp_threshold` should be a configurable variable or a constant. The user that collects more than `stamp_threshold` sponsor + community stamps can win a prize at the end of the conference.

The `rank_threshold` should be a configurable variable or a constant. The top ranked users can win a prize at the end of the conference.

The `phishing_penalty` should be a configurable variable or a constant, indicating the penalty of clicking a phishing link.

The current score calculation formula is `score = 10 * num_of_collection`. This formula may be finalized or changed in the future.

The `freeze_timeout` should be a configurable variable or a constant, indicating how long a scoreboard can stay in `FREEZING` before it is considered stale.

## Before Conference Starts

The user will receive an email, containing a link like `https://game.hitcon2026.online/b?whatever={whatever_related_to_the_user}`. This is hosted elsewhere, and will redirect to app store to download the mobile app.

After downloading the app, the user will somehow setup the app, and somehow the app will obtain their JWT token.

The app will then make a query to `GET /users/me`, triggering lazy initialization of the user's profile. The user can use `PATCH /users/me` to update their profile before the conference starts.

## When Conference Starts, at Reception Desk

The user will pick up a NFC tag, open the app, and scan the tag using the app. The app will use `POST /tags/pair` to link their profile to the NFC tag's physical ID.

Also, the app will write a URL `https://game.hitcon2026.online/b?u={user_id}` to the tag. Again, this is hosted elsewhere. The URL will redirect the mobile device to open the app.

After the app writes the URL to the tag, it will lock (encrypt) the tag, so it is only readable. This will make sure the tag won't be accidentally overwritten.

## During the Conference

The user can still use `PATCH /users/me` to update their profile at any time.

The user can use `GET /users/{user_id}` to view other's profile. If the physical ID of the queried user is provided as the `physical_id` query parameter, our API server will return all data of the user; otherwise, our API server will return only "display name" and "emoji icon". (The mobile app will show a "locked character" indicator if the user's physical ID is not presented)

### Scanning Other's NFC Tag

Whenever a user use their mobile device to scan other's NFC Tag,

1. The URL written in the tag will open the app. (something like `https://game.hitcon2026.online/b?u={user_id}`)
2. The app will read the tag's physical ID.
3. The app will read the URL written in the tag, and then extract the user ID in the URL.
4. The app will send a request to `POST /collection/scan`, using the scanner's (the app's owner) JWT token to authenticate, and the physical ID and the parsed user ID as request body.
5. Our API server will check whether the physical ID is related to the parsed user ID.
6. Our API server will add the parsed user ID to the scanner's collection.
7. Our API server will insert a record if this is the first time of collecting this NFC tag.
8. Our API server will return success.
9. The app will use `GET /users/{user_id}` to query the newly collected user's profile, and show it on the page.

Note that the NFC tag's physical ID are serial, so the user can easily predict other tag's physical ID. Therefore, it is necessary to also send the parsed user ID to prevent malicious user from faking a scan.

### Phishing

If the mobile app is triggered by clicking a link (like `https://game.hitcon2026.online/b?u={user_id}`) instead of scanning a tag, the app will not detect a physical ID. Then, the app will send request to `POST /collections/phishing` with `victim` and `attacker`. Our API server will record this event and apply score penalty to the victim after the scoreboard is frozen.

### Missions

The user can use `GET /missions/stamp` to see `stamp_threshold` and their progress of winning that prize.

### Scoreboard

The user can use `GET /scoreboard` with `offset` and `limit` to query the global scoreboard.

## Near the End of the Conference

When the conference is about to end, someone will make a request to `POST /staff/freeze_scoreboard` with a `STAFF_DANGER_TOKEN` to freeze the scoreboard. Then, the server will calculate the stamp prize and scoreboard prize.

The freeze operation should calculate the final scores and prize results once, then store a per-user result snapshot. This snapshot should be used by `GET /users/me/prize`; do not recalculate prize results on every prize lookup.

To avoid race conditions and support resume, the scoreboard should use a state machine: `OPEN`, `FREEZING`, and `FROZEN`. `POST /staff/freeze_scoreboard` should atomically change `OPEN` to `FREEZING`, calculate and store results for a new `freeze_id`, then change the state to `FROZEN`. If another freeze request arrives while the state is `FREEZING` or `FROZEN`, the server should reject it.

If the scoreboard stays in `FREEZING` longer than `freeze_timeout`, the freeze is considered stale. Partial results for that `freeze_id` should not be visible to users, because `GET /users/me/prize` only reads a stored snapshot when the scoreboard state is `FROZEN`.

The API server should provide `GET /staff/scoreboard_status` with a `STAFF_DANGER_TOKEN` so staff can inspect the current scoreboard state, current `freeze_id`, and freeze timestamps.

Also, the API server has an endpoint `POST /staff/resume_scoreboard` to resume the accidentally frozen scoreboard. Requires `STAFF_DANGER_TOKEN`, too. Resume should change `FROZEN` back to `OPEN` and invalidate the stored result snapshot for the current `freeze_id`; the next freeze will calculate a new snapshot. Resume can also recover a stale `FREEZING` state by changing it back to `OPEN` and invalidating partial results for the stale `freeze_id`.

The user can lookup their prize after the scoreboard is frozen via `GET /users/me/prize`.
