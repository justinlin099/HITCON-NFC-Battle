import { describe, expect, it } from "vitest";
import {
  authHeaders,
  createTestServer,
  initializeUser,
  jsonRequest,
  pairTag,
  readJson,
  staffHeaders,
} from "./helpers";

describe("external prize claims", () => {
  it("invalidates scoreboard caches only for external claims", async () => {
    const server = await createTestServer();
    await initializeUser(server, "alice");
    await initializeUser(server, "bob");
    await initializeUser(server, "carol");

    const getCacheVersion = async () => {
      const row = await server.db
        .prepare("SELECT version FROM prize_claims_state WHERE id = 1")
        .first<{ version: number }>();
      return row?.version;
    };

    expect(await getCacheVersion()).toBe(0);

    await server.db
      .prepare(
        `
        INSERT INTO prize_claims (type, freeze_id, user_id, claimed_by_user_id)
        VALUES ('STAMP', '', 'alice', 'staff')
        `,
      )
      .run();
    expect(await getCacheVersion()).toBe(0);

    await server.db
      .prepare(
        `
        INSERT INTO prize_claims (type, freeze_id, user_id, claimed_by_user_id)
        VALUES ('RANKING', 'freeze-test', 'bob', 'staff')
        `,
      )
      .run();
    expect(await getCacheVersion()).toBe(0);

    await server.db
      .prepare(
        `
        INSERT INTO prize_claims (type, freeze_id, user_id, claimed_by_user_id)
        VALUES ('EXTERNAL', '', 'carol', 'staff')
        `,
      )
      .run();
    expect(await getCacheVersion()).toBe(1);
  });

  it("lets staff claim an externally-awarded prize once and check its status", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const staffAuth = await authHeaders("staff", "STAFF");

    await initializeUser(server, "alice");
    await pairTag(server, aliceAuth, "uid-alice");

    const before = await server.request("/staff/prize-claims/alice?type=EXTERNAL", {
      headers: staffAuth,
    });
    expect(before.status).toBe(200);
    await expect(readJson(before)).resolves.toMatchObject({
      data: {
        user_id: "alice",
        type: "EXTERNAL",
        freeze_id: null,
        claimed: false,
        claimed_at: null,
        claimed_by_user_id: null,
      },
    });

    const redemption = await server.request(
      "/staff/prize-claims",
      await jsonRequest(
        "POST",
        { user_id: "alice", uid: "uid-alice", type: "EXTERNAL" },
        staffAuth,
      ),
    );
    expect(redemption.status).toBe(200);
    await expect(readJson(redemption)).resolves.toMatchObject({
      data: { user_id: "alice", type: "EXTERNAL", claimed_by_user_id: "staff" },
    });

    const after = await server.request("/staff/prize-claims/alice?type=EXTERNAL", {
      headers: staffAuth,
    });
    await expect(readJson(after)).resolves.toMatchObject({
      data: { user_id: "alice", type: "EXTERNAL", claimed: true, claimed_by_user_id: "staff" },
    });

    const scoreboard = await server.request("/scoreboard", { headers: aliceAuth });
    await expect(readJson(scoreboard)).resolves.toMatchObject({
      data: {
        rankings: [
          { user_id: "alice", external_prize: true },
        ],
      },
    });

    const frozen = await server.request("/staff/freeze_scoreboard", {
      method: "POST",
      headers: { ...staffAuth, ...staffHeaders() },
    });
    expect(frozen.status).toBe(200);

    const frozenScoreboard = await server.request("/scoreboard", { headers: aliceAuth });
    await expect(readJson(frozenScoreboard)).resolves.toMatchObject({
      data: {
        frozen: true,
        rankings: [
          { user_id: "alice", external_prize: true },
        ],
      },
    });

    const duplicate = await server.request(
      "/staff/prize-claims",
      await jsonRequest(
        "POST",
        { user_id: "alice", uid: "uid-alice", type: "EXTERNAL" },
        staffAuth,
      ),
    );
    expect(duplicate.status).toBe(409);
    await expect(readJson(duplicate)).resolves.toMatchObject({
      code: "PRIZE_ALREADY_CLAIMED",
    });
  });

  it("requires a paired NFC UID when redeeming an external prize", async () => {
    const server = await createTestServer();
    const staffAuth = await authHeaders("staff", "STAFF");

    await initializeUser(server, "alice");
    await pairTag(server, await authHeaders("alice"), "uid-alice");

    const response = await server.request(
      "/staff/prize-claims",
      await jsonRequest(
        "POST",
        { user_id: "alice", uid: "wrong-uid", type: "EXTERNAL" },
        staffAuth,
      ),
    );

    expect(response.status).toBe(403);
    await expect(readJson(response)).resolves.toMatchObject({ code: "PHYSICAL_ID_MISMATCH" });
  });
});
