# Game Flow

A valid value for user's role:
* attendee (`ATTENDEE`)
* staff (`STAFF`)
* sponsor (`SPONSOR`)
* community (`COMMUNITY`)

A user's data contains:
* user ID (the hashed KKTIX user ID or whatever provided by JWT's issuer)
* display name
* user role
* emoji icon
* bio
* pixel_avatar_base64
* NFC tag's physical ID
* profile version
* collection version

The collection table records which user IDs a user has previously scanned. A collection record is also the long-term permission that lets the scanner view the collected user's full profile.

`profile_version` and `collection_version` are integer versions stored on the user row. `profile_version` changes when profile fields change. `collection_version` changes only when that user's own collection changes. For example, when Alice scans Bob, Alice's `collection_version` changes, but Alice's `profile_version`, Bob's `profile_version` and `collection_version` do not change.

The `stamp_threshold` should be a configurable variable or a constant. The user that collects more than `stamp_threshold` sponsor + community stamps can win a prize at the end of the conference.

The `rank_threshold` should be a configurable variable or a constant. The top ranked users can win a prize at the end of the conference.

The `phishing_penalty` should be a configurable variable or a constant, indicating the penalty of clicking a phishing link.

The current score calculation formula is `score = 10 * num_of_collection`. This formula may be finalized or changed in the future.

The `freeze_timeout` should be a configurable variable or a constant, indicating how long a scoreboard can stay in `FREEZING` before it is considered stale. The default should be 30 seconds.

JWT verification is simple: the backend verifies the token with a shared secret and HMAC. The JWT must contain `sub`, `exp`, `iss`, `aud`, and `role`. The JWT subject (`sub`) is the user's ID. The `role` claim is used for fast role lookup, so the backend does not need to query the database just to check the caller's role.

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

### Scanning Other's NFC Tag

Whenever a user use their mobile device to scan other's NFC Tag,

1. The URL written in the tag will open the app. (something like `https://game.hitcon2026.online/b?u={user_id}`)
2. The app will read the tag's physical ID.
3. The app will read the URL written in the tag, and then extract the user ID in the URL.
4. The app will send a request to `POST /collection/scan`, using the scanner's (the app's owner) JWT token to authenticate, and the physical ID and the parsed user ID as request body.
5. Our API server will check whether the physical ID is related to the parsed user ID.
6. Our API server will add the parsed user ID to the scanner's collection.
7. Our API server will insert a record if this is the first time of collecting this NFC tag.
8. If the inserted collection record is new, our API server will increment the scanner's `collection_version`.
9. Our API server will return success and the scanned user's profile without that user's collection list.
10. The app can show the scanned user's profile immediately without making another profile request.

Note that the NFC tag's physical ID are serial, so the user can easily predict other tag's physical ID. Therefore, it is necessary to also send the parsed user ID to prevent malicious user from faking a scan.

### Viewing Other's Profile on App

When the app wants to display another user's profile, it calls
`GET /users/{user_id}` with the viewer's JWT.

If the viewer has collected the queried user, the API server returns the queried user's full profile, `profile_version`, and `collection_version`, but does not include the queried user's collection list in this response.

* If the viewer has not collected the queried user, the API server returns only `user_id`, `display_name` and `emoji_icon`.
* If the viewer sends both `profile_version` and `collection_version` to `GET /users/{user_id}`, and both match the server's current versions, the API server returns only `user_id` and `unchanged: true`.
* If either cached version is omitted or stale, `GET /users/{user_id}` returns the user's profile body using the normal visibility rule.
* If the viewer has collected the queried user, and the app already has a cached full profile but sees that the queried user's `collection_version` is newer than the local cache, the app can call `GET /users/{user_id}/collection` to refresh that queried user's collection list.

`GET /users/{user_id}/collection` returns the queried user's collection only when the viewer has collected the queried user. If the viewer has not collected the queried user, the API server returns a forbidden error. The viewer may send `collection_version`; if it matches the server's current collection version for the queried user, the API server returns only `user_id` and `unchanged: true`. Otherwise, for each user in that collection list, the API server applies the same profile visibility rule from the viewer's point of view. If the viewer has collected that listed user, return that listed user as full profile data. Otherwise, return only `user_id`, `display_name`, and `emoji_icon`.

The app can use `POST /users/batch` to refresh multiple cached user profiles in one request. This endpoint is read-only and uses `POST` only so the app can send a structured request body. The request contains a list of user IDs and optional locally cached `profile_version` and `collection_version` values. For each requested user, the API server applies the same profile visibility rule from the viewer's point of view. If both cached versions are provided and both match the server's current versions, it returns only `user_id` and `unchanged: true`. Otherwise, it returns `unchanged: false` and the requested user's profile using the same response shape as `GET /users/{user_id}`: full profile data when the viewer has collected that user, or only `user_id`, `display_name`, and `emoji_icon` when the viewer has not collected that user. The batch request should have a maximum item count so one request cannot read an unbounded number of user rows.

Example:

* Alice collected Bob.
* Alice has not collected Carol.
* Bob collected Carol.
* Alice opens Bob's collection list via `GET /users/Bob/collection`.
* Carol appears with only `user_id`, `display_name`, and `emoji_icon`. `GET /users/Carol/collection` should return a forbidden error.
* Later, Alice collects Carol.
* When Alice opens Bob's collection list again, Carol appears as full profile data because Alice has now collected Carol.

### Phishing

If the mobile app is triggered by clicking a link (like `https://game.hitcon2026.online/b?u={user_id}`) instead of scanning a tag, the app will not detect a physical ID. Then, the app will send request to `POST /collection/phishing` with `victim` and `attacker`. Our API server will record this event. The freeze calculation applies the phishing penalty to eligible phishing events in the stored score snapshot.

### Missions

The user can use `GET /missions/stamp` to see `stamp_threshold` and their progress of winning that prize.

### Scoreboard

The user can use `GET /scoreboard` with `offset` and `limit` to query the global scoreboard. While the scoreboard state is `OPEN`, this endpoint returns live scores. While the scoreboard state is `FREEZING`, this endpoint should be rejected because a consistent snapshot is being calculated. While the scoreboard state is `FROZEN`, this endpoint returns the stored freeze snapshot, so scores do not change even if the app continues to record pairing, scanning, phishing, profile, and collection updates.

### In Case of Someone Lost Their App

If the user somehow resets their app or needs a fresh installation, the app can use `GET /users/me/bootstrap` to restore the local cache in 1 request:

* the full user profile of themselves
* the user's `profile_version` and `collection_version`
* the full profile of every previously collected user, without each collected user's collection list
* each collected user's `profile_version` and `collection_version`

The endpoint is equal to `GET /users/me`, `GET /users/{user_id}`, and `GET /users/{user_id}/collection`. Using this endpoint can reduce the server load by only requiring 1 request.

This endpoint is for app bootstrap and recovery. Normal refresh should still use `GET /users/me`, `GET /users/{user_id}/collection`, and `POST /users/batch` so the app does not repeatedly download all collected profiles.

## Near the End of the Conference

When the conference is about to end, someone will make a request to `POST /staff/freeze_scoreboard` with a `STAFF_DANGER_TOKEN` to freeze the scoreboard. The request may include `scoring_cutoff_at` to specify the latest event timestamp that should count in the score snapshot. If `scoring_cutoff_at` is omitted, the server uses its current time. Then, the server will calculate the stamp prize and scoreboard prize.

The freeze operation should calculate the final scores and prize results once, using only collection records and phishing records whose event timestamps are less than or equal to `scoring_cutoff_at`, then store a per-user result snapshot. This snapshot should be used by `GET /scoreboard` and `GET /users/me/prize` while the scoreboard state is `FROZEN`; do not recalculate scoreboard or prize results on every lookup.

To avoid race conditions and support resume, the scoreboard should use a state machine: `OPEN`, `FREEZING`, and `FROZEN`. `POST /staff/freeze_scoreboard` should atomically change `OPEN` to `FREEZING`, calculate and store results for a new `freeze_id`, then change the state to `FROZEN`. If another freeze request arrives while the state is `FREEZING` or `FROZEN`, the server should reject it.

If the scoreboard stays in `FREEZING` longer than `freeze_timeout`, the freeze is considered stale. Partial results for that `freeze_id` should not be visible to users, because `GET /users/me/prize` only reads a stored snapshot when the scoreboard state is `FROZEN`.

The app should keep working after the scoreboard is frozen. `PATCH /users/me`, `POST /tags/pair`, `POST /collection/scan`, `POST /collection/phishing`, profile lookup, collection lookup, bootstrap, batch refresh, and mission progress continue to use and update live app data after the conference ends. These later live updates must not change the stored score and prize snapshot unless staff explicitly resumes scoring and freezes again.

The API server should provide `GET /staff/scoreboard_status` with a `STAFF_DANGER_TOKEN` so staff can inspect the current scoreboard state, current `freeze_id`, and freeze timestamps.

Also, the API server has an endpoint `POST /staff/resume_scoreboard` to resume the accidentally frozen scoreboard. Requires `STAFF_DANGER_TOKEN`, too. Resume should change `FROZEN` back to `OPEN` and invalidate the stored result snapshot for the current `freeze_id`; the next freeze will calculate a new snapshot. Resume can also recover a stale `FREEZING` state by changing it back to `OPEN` and invalidating partial results for the stale `freeze_id`.

The user can lookup their prize after the scoreboard is frozen via `GET /users/me/prize`.
