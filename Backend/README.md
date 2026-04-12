# HITCON 2026 NFC Tag Game API Specification

## System Architecture and Global Config

- **Base URL (Production):** `https://game.hitcon2026.online/v1`
- **Base URL (Development):** `https://<ngrok-or-local-domain>/v1`
- **Content-Type:** `application/json`
- **Authentication:** Every request must include the conference SSO JWT in the header.
  - `Authorization: Bearer <SSO_JWT_Token>`
- **User Identification (User ID):** The backend always uses `sub` from the JWT payload (usually a hash of the KKTIX ID) as the primary key. Never trust user IDs provided by the frontend.

### NFC Tag URL and Redirect Entry

- **Tag URL template (stored in every NFC tag):** `https://game.hitcon2026.online/b?u={user_id}`
- **Behavior:** When a client app scans a tag, it opens this URL and is redirected by our service.
- **Purpose of `u`:** The `u` query parameter carries the target user id encoded in the tag URL.
- **Trust model:** `u` is untrusted input from the physical tag and must be verified with physical UID during `POST /collections/scan`.
- **Scope note:** `/b` is a redirect entry endpoint for scan flow and is outside the authenticated `/v1` API surface.

### Required JWT Claims

- `sub` (required): Stable unique user identifier. Requests without `sub` should be rejected as `401 Unauthorized`.
- `exp` (required): Expiration time. Expired tokens must be rejected.
- `iss` (required): Token issuer. Must match the configured SSO issuer.
- `aud` (required): Token audience. Must match this API's configured audience.
- `role` (conditionally required): Required for staff-only APIs, must be `STAFF` when calling `/staff/*` endpoints.

Example JWT payload:

```json
{
  "sub": "kktix_hash_abc123",
  "iss": "https://sso.hitcon2026.online",
  "aud": "hitcon-nfc-tag-game-api",
  "exp": 1786242000,
  "role": "ATTENDEE"
}
```

---

## Unified Error Responses and Security Gatekeeping

Frontend app developers should handle the following status codes in an API interceptor and present the matching UI.

- **401 Unauthorized (authentication failed):**
  - Trigger: Token is expired, invalid, or missing.
  - `{"status": "error", "code": "UNAUTHORIZED", "message": "Invalid or expired JWT token."}`
- **403 Forbidden (insufficient permission / anti-forgery block):**
  - Trigger A (staff APIs): A normal attendee calls staff-only APIs.
  - Trigger B (core anti-forgery): During `POST /collections/scan`, the target user id does not match the scanned physical NFC UID (treated as replay attack or cloned tag).
  - `{"status": "error", "code": "SECURITY_VERIFICATION_FAILED", "message": "UID mismatch or insufficient permissions."}`
- **404 Not Found (resource does not exist):**
  - Trigger: Scanning an unpaired blank NFC tag, or requesting a non-existent user.
  - `{"status": "error", "code": "UID_NOT_FOUND", "message": "User or physical tag does not exist."}`
- **409 Conflict (resource conflict):**
  - Trigger: Trying to pair an NFC tag that is already paired to another user.
  - `{"status": "error", "code": "TAG_ALREADY_IN_USE", "message": "This NFC tag is already bound to another user."}`

---

## 1. Profile and Hardware Binding

### 1. Initialize / Get My Profile
- **Endpoint:** `GET /users/me`
- **Backend logic:** Lazy initialization. If `sub` from JWT does not exist in the database, the backend should create a default profile automatically.
- **Response (200 OK):**
```json
{
  "status": "success",
  "data": {
    "user_id": "sub_hash_from_jwt",
    "display_name": "Hacker_Aries",
    "user_type": "CAT",
    "emoji_icon": "cat",
    "bio": "I love reverse engineering.",
    "pixel_avatar_base64": "iVBORw0KGgoAAAANSU...",
    "stats": {
      "score": 450,
      "tags_collected": 45
    }
  }
}
```

### 2. Update My Profile
- **Endpoint:** `PATCH /users/me`
- **Request Body:** (all fields are optional)
```json
{
  "display_name": "Aries_The_Great",
  "user_type": "TECH",
  "bio": "Updated bio.",
  "pixel_avatar_base64": "iVBORw0KGgo..."
}
```
- **Response (200 OK):** `{"status": "success", "message": "Profile updated."}`

### 3. View Another User's Collection
- **Endpoint:** `GET /users/{target_id}/collection`
- **Response (200 OK):**
```json
{
  "status": "success",
  "data": {
    "owner_display_name": "Cool_Doggy",
    "total_collected": 12,
    "collection": [
      {
        "user_id": "U_1X2Y3Z",
        "display_name": "Plant_Lover",
        "emoji_icon": "plant",
        "collected_at": "2026-04-12T10:30:00Z"
      }
    ]
  }
}
```

### 4. Pair Physical NFC Tag (Reception Check-in at Conference Start)
- **Endpoint:** `POST /tags/pair`
- **When this is used:** This endpoint is used when the conference starts and an attendee arrives at the reception table. Staff or the attendee app reads the physical NFC UID and calls this endpoint to pair that UID to the attendee account.
- **Request Body:**
```json
{
  "physical_uid": "04:1A:2B:3C:4D:5E:6F" // Physical hardware UID
}
```
- **Response (200 OK):** `{"status": "success", "message": "Tag paired successfully."}`

---

## 2. Gameplay Core

### 5. Physical Scan Collection (NFC Tag Exchange 名片交換 / Sponsor Stand and Community Stand Stamps 攤位集點)
Flow: An attendee scans another attendee tag, sponsor stand tag, or community stand tag. The scanned URL opens `https://game.hitcon2026.online/b?u={user_id}` and the app is redirected by our service, then posts the scanned tag data to the server. The server verifies the scan, determines the target type, and responds with the scanned tag info. The app then uses this response data to update local app storage. **The backend must strictly verify UID to prevent tag cloning. (i.e. someone modifies the `u` value / `target_user_id` in their tag URL)**

- **Endpoint:** `POST /collections/scan`
- **Request Body:**
```json
{
  "target_user_id": "U_9V8W7X",             // Parsed from query parameter `u` in the scanned tag URL
  "scanned_nfc_uid": "04:99:88:77:66:55:44" // Read from NFC hardware
}
```
- **Response (200 OK, target is attendee):**
```json
{
  "status": "success",
  "type": "ATTENDEE",
  "data": {
    "target_info": {
      "user_type": "CAT",
      "emoji_icon": "cat",
      "total_tags": 45
    },
    "ciphertext": "U2FsdGVkX1+xxyz...", // For client-side decryption in app
    "pixel_avatar_base64": "iVBORw0KGgo..."
  }
}
```
- **Response (200 OK, target is sponsor stand):**
```json
{
  "status": "success",
  "type": "SPONSOR_STAND",
  "data": {
    "sponsor_stand_id": "sp_01",
    "sponsor_stand_name": "Google",
    "sponsor_stand_message": "Welcome to Google! We are hiring.",
    "current_stamps": 9,
    "required_for_prize": 10
  }
}
```
- **Response (200 OK, target is community stand):**
```json
{
  "status": "success",
  "type": "COMMUNITY_STAND",
  "data": {
    "community_stand_id": "cs_01",
    "community_stand_name": "g0v",
    "community_stand_message": "Don't ask why nobody does. You are the nobody.",
    "current_stamps": 9,
    "required_for_prize": 10
  }
}
```

### 6. Phishing Easter Egg Trigger (Social Engineering Trap)
Triggered when the app is opened via a clicked link and no physical NFC signal is detected.

- **Endpoint:** `POST /collections/phishing`
- **Request Body:**
```json
{
  "target_user_id": "U_9V8W7X"
}
```
- **Response (200 OK, special state):**
```json
{
  "status": "phished",
  "data": {
    "alert_title": "Social Engineering Alert!",
    "alert_message": "You clicked an untrusted link. Return to the real world and tap the physical NFC tag.",
    "score_penalty": -20
  }
}
```

---

## 3. Missions and Scoreboard

### 7. Get Sponsor Stand Stamp Progress
- **Endpoint:** `GET /missions/sponsor-stands`
- **Response (200 OK):**
```json
{
  "status": "success",
  "data": {
    "collected_count": 8,
    "required_for_prize": 10,
    "sponsor_stands": [
      { "id": "sp_01", "name": "Google", "status": "collected" },
      { "id": "sp_02", "name": "Microsoft", "status": "pending" }
    ]
  }
}
```

### 8. Get Community Stand Stamp Progress
- **Endpoint:** `GET /missions/community-stands`
- **Response (200 OK):**
```json
{
  "status": "success",
  "data": {
    "collected_count": 4,
    "required_for_prize": 10,
    "community_stands": [
      { "id": "cs_01", "name": "g0v", "status": "collected" },
      { "id": "cs_02", "name": "OWASP Taiwan", "status": "pending" }
    ]
  }
}
```

### 9. Global Scoreboard
- **Endpoint:** `GET /scoreboard/global`
- **Query Params:** `?limit=50`
- **Response (200 OK):**
```json
{
  "status": "success",
  "data": {
    "last_updated": "2026-04-12T15:00:00Z",
    "rankings": [
      { "rank": 1, "display_name": "Root_User", "score": 2500, "emoji_icon": "laptop" },
      { "rank": 2, "display_name": "CTF_Player", "score": 2480, "emoji_icon": "cat" }
    ]
  }
}
```

---

## 4. Staff Quick Validation (Staff Only)

**Authorization requirement:** JWT payload for this API group must include `role: "STAFF"`.

### 10. Verify Identity by Physical NFC Scan
Staff can scan an attendee's physical NFC tag with a phone to retrieve identity and prize eligibility.

- **Endpoint:** `GET /staff/identify/{nfc_uid}`
- **Response (200 OK):**
```json
{
  "status": "success",
  "data": {
    "user_id": "sub_hash_from_jwt",
    "display_name": "Hacker_Aries",
    "pixel_avatar_base64": "iVBORw0K...",
    "eligibility": {
      "sponsor_stand_prize": { "can_redeem": true, "already_redeemed": false },
      "community_stand_prize": { "can_redeem": true, "already_redeemed": false },
      "scoreboard_prize": { "can_redeem": false, "reason": "Ranked #87 (Not in Top 10)" }
    }
  }
}
```

### 11. Confirm Prize Redemption
- **Endpoint:** `POST /staff/redeem`
- **Request Body:**
```json
{
  "user_id": "sub_hash_from_jwt",
  "prize_category": "SPONSOR_STAND" // or "COMMUNITY_STAND" or "SCOREBOARD"
}
```
- **Response (200 OK):** `{"status": "success", "message": "Prize redeemed successfully."}`

