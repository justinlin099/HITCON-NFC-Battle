# Backend Open Decisions

Every entry here is **blocking some piece of implementation**. Code that
references one of these IDs (`TODO(<id>):` in source) cannot land until the
decision is recorded here as **Decided** with a date and rationale.

Status legend: 🔴 blocking · 🟡 has workaround · 🟢 decided

---

## 🟢 score-rules — Score formula, cooldown, dedup

**Decided 2026-05-24:**

- Attendee scan: **scanner +10**, target +0
- Stand scan (both sponsor & community): **scanner +20**, stand owner +0
- One-shot per `(scanner, target)` pair — second scan of the same target awards 0 points but still returns the target info (enforced by `scans_unique_scanner_target` index).
- **Asymmetric** — only the scanner earns. "兩邊都要掃 不能一邊掃兩邊就拿到": for A and B to both score, A must scan B **and** B must scan A.
- `tags_collected` increments only on attendee scans (the "name-card collection"); stand scans count toward missions, not the collection.

**Open sub-question (assumed but not confirmed):** sponsor and community stands are both worth 20. If they should differ, say so and I'll split.

---

## 🔴 ciphertext-payload — `ciphertext` field in scan response

**Blocks:** [`POST /collections/scan`](src/routes/collections.ts) attendee response shape.

[`Backend/README.md`](../README.md#L156) shows `"ciphertext": "U2FsdGVkX1+xxyz..."` "for client-side decryption in app" with no further definition. Need:

- What is encrypted? (target profile? a per-scan token?)
- Key distribution? (per-user? per-event? embedded in app?)
- Why does the client need to decrypt something the server just sent it over TLS?

**Recommendation:** drop the field unless there's a concrete threat model. If kept, document algorithm + key lifecycle.

---

## 🔴 stand-identity — Stand tag model & Staff-as-stand fallback

**Blocks:** [`POST /collections/scan`](src/routes/collections.ts), [`GET /staff/identify`](src/routes/staff.ts).

Current schema (`stands.owner_user_id` + `staff_assignments`) supports both:

- Dedicated stand NTAG card → `tags.stand_id` set → resolve directly.
- Staff badge scanned at a stand without a card → look up `staff_assignments[staff_user_id] → stand_id`.

Need to confirm with organizers:

- Will every stand have a stand card, or only some?
- Can one Staff be assigned to multiple stands concurrently? Over time?
- Does the staff-as-stand fallback also grant **the staff** an attendee-style scan credit, or only the scanner?

---

## 🔴 phishing-trust — Phishing detection trust model

**Blocks:** [`POST /collections/phishing`](src/routes/collections.ts).

Spec says "triggered when the app is opened via a clicked link and no physical NFC signal is detected" — that's a client-side assertion. Options:

1. **Trust the client.** Phishing penalty is opt-in flavor; abusers just never call it. (Cheapest, harmless if score impact is small.)
2. **Server-issued nonce in NFC writes only.** Real tags carry `?u=…&n=<nonce>`; the public landing page never sees the nonce. Scan endpoint requires it; phishing endpoint requires absence + a fresh `?u=` referer chain.
3. **Drop the feature.**

**Recommendation:** (1) with `score_penalty` ≤ a single attendee scan, so the worst case is parity with not playing.

---

## 🔴 prize-threshold-scope — Per-stand or global threshold?

**Blocks:** [`GET /missions/sponsor-stands`](src/routes/missions.ts), [`GET /missions/community-stands`](src/routes/missions.ts), staff eligibility checks.

Spec response has a single `required_for_prize` at the top level, but in practice different stands might have different prize thresholds. Current schema stores it per stand (`stands.required_for_prize`); the handler currently echoes the first stand's value. Confirm whether it's actually global.

---

## 🔴 scoreboard-prize-rules — Top-N + freeze time

**Blocks:** [`GET /staff/identify`](src/routes/staff.ts) eligibility for `scoreboard_prize`.

Need: how many ranks win? When does the leaderboard freeze for prize purposes (end of Day 2? a published cutoff time?)? Tie-breaking rule?

---

## 🔴 redemption-uniqueness — One-shot vs daily vs per-prize

**Blocks:** [`POST /staff/redeem`](src/routes/staff.ts).

Schema currently enforces one redemption per `(user_id, prize_category)` via `redemptions_unique`. Confirm:

- Is this correct, or can the same category be redeemed multiple times (e.g. one sponsor prize per sponsor)?
- If multi, the schema needs `(user_id, prize_category, prize_instance_id)`.

---

## 🟡 repair-flow — Re-pair / unbind a tag

**Blocks:** edge case for lost or damaged badges (not the happy path).

Current `POST /tags/pair` returns `409 TAG_ALREADY_IN_USE` if the UID is taken by someone else. We have no staff-only override. Workaround: do it directly in D1 console at the event. Proper fix: `POST /staff/tags/repair` with audit log entry.

---

## 🟡 collection-pagination — `GET /users/:id/collection` size

**Blocks:** payload bloat for power users (and the scoreboard top players, who will be scanned the most by curious onlookers).

Currently returns the entire collection in one response. Workable for ~2k attendees but should add cursor pagination before opening to public viewing.

---

## 🟡 profile-vocab — `user_type`, `emoji_icon` enums and field limits

**Blocks:** validation in [`PATCH /users/me`](src/routes/users.ts).

Spec uses `"CAT"`, `"TECH"`, etc. without an explicit list. Currently the backend accepts arbitrary strings (no validation). App side needs to lock down the enum + max lengths (display_name, bio, base64 size cap) so we can enforce server-side too.

---

## 🟡 scoreboard-freshness — Cache TTL on `/scoreboard/global`

**Blocks:** load handling during prize hour.

Currently uncached — fine for development. Wrap in Workers Cache API (e.g. 15–30s TTL) once scan handler is wired, so the inevitable refresh spike doesn't hammer D1.

---

## 🟡 cors-scope — Allowed origins for `/v1/*`

**Blocks:** nothing yet (CORS is `*`). Tighten once we know whether `/b` landing page or any browser surface calls the API.

---

## 🟢 Decided

- `score-rules` (2026-05-24) — see above.

---

## How to close an entry

When a decision lands:

1. Move the entry's heading to 🟢 and add `**Decided YYYY-MM-DD:** <one-line summary>`.
2. Remove the corresponding `TODO(<id>):` from source.
3. Update [`Backend/README.md`](../README.md) if the public contract changed.
