import { Hono } from "hono";
import { requireAuth, requireStaff } from "../middleware/auth";
import { errorResponse } from "../lib/errors";
import type { AppEnv } from "../types";

export const staffRoute = new Hono<AppEnv>();

staffRoute.use("*", requireAuth, requireStaff);

// GET /staff/identify/:nfc_uid
// -----------------------------------------------------------------------------
// BLOCKED — see DECISIONS.md:
//   - "Scoreboard prize rules" : `eligibility.scoreboard_prize` needs the
//                                rank threshold and the freeze-time policy.
//   - "Prize threshold scope"  : sponsor/community eligibility depends on
//                                whether the threshold is global or per-stand.
//
// Sketch:
//   1. Look up tag by `nfc_uid` → owner user_id; 404 if unpaired.
//   2. Load user profile (display_name, pixel_avatar_base64).
//   3. Compute eligibility per prize category:
//        - sponsor_stand_prize  : enough distinct SPONSOR_STAND scans?
//        - community_stand_prize: enough distinct COMMUNITY_STAND scans?
//        - scoreboard_prize     : rank within configured top-N?
//      and check `redemptions` for already_redeemed.
// -----------------------------------------------------------------------------
staffRoute.get("/identify/:nfc_uid", async (c) => {
  return errorResponse(
    c,
    "INTERNAL_ERROR",
    "Not implemented — pending decisions on prize-threshold scope and scoreboard prize rules.",
  );
});

// POST /staff/redeem
// -----------------------------------------------------------------------------
// BLOCKED — see DECISIONS.md "Redemption uniqueness".
// Schema already enforces one redemption per (user, category) via the unique
// index, but we need to confirm that's the desired policy (vs per-day, or per
// prize-instance) before wiring the handler.
//
// Sketch:
//   1. Verify caller is STAFF (done by middleware).
//   2. Re-check eligibility (same logic as /staff/identify).
//   3. Insert into `redemptions`; rely on unique index to reject duplicates.
//   4. Append `audit_log` entry with actor = staff sub, target = user_id.
// -----------------------------------------------------------------------------
staffRoute.post("/redeem", async (c) => {
  return errorResponse(
    c,
    "INTERNAL_ERROR",
    "Not implemented — pending decision on redemption uniqueness policy.",
  );
});
