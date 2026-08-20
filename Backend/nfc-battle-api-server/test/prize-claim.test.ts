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

describe("staff prize claims", () => {
  it("claims an eligible prize once and rejects ineligible or repeat claims", async () => {
    const server = await createTestServer();
    const alice = await initializeUser(server, "alice");
    const bob = await initializeUser(server, "bob");
    const carol = await initializeUser(server, "carol");
    await pairTag(server, alice.headers, "uid-alice");
    await pairTag(server, bob.headers, "uid-bob");
    await pairTag(server, carol.headers, "uid-carol");

    const dangerHeaders = {
      ...(await authHeaders("staff", "STAFF")),
      ...staffHeaders(),
    };
    expect(
      (await server.request("/staff/freeze_scoreboard", { method: "POST", headers: dangerHeaders })).status,
    ).toBe(200);
    await server.db
      .prepare(
        "UPDATE prize_results SET stamp_prize = 0, rank_prize = 0 WHERE user_id = ?1",
      )
      .bind("bob")
      .run();
    await server.db
      .prepare(
        "UPDATE prize_results SET stamp_prize = 1, rank_prize = 1 WHERE user_id = ?1",
      )
      .bind("carol")
      .run();

    const staffJwt = await authHeaders("staff", "STAFF");
    const claimAlice = async () => server.request(
      "/staff/prize-claims",
      await jsonRequest(
        "POST",
        { user_id: "alice", uid: "uid-alice", type: "RANKING" },
        staffJwt,
      ),
    );
    expect((await claimAlice()).status).toBe(200);

    const claimCarol = async (type: "RANKING") => server.request(
      "/staff/prize-claims",
      await jsonRequest("POST", { user_id: "carol", uid: "uid-carol", type }, staffJwt),
    );
    expect((await claimCarol("RANKING")).status).toBe(200);

    const duplicate = await claimAlice();
    expect(duplicate.status).toBe(409);
    await expect(readJson(duplicate)).resolves.toMatchObject({ code: "PRIZE_ALREADY_CLAIMED" });

    const ineligible = await server.request(
      "/staff/prize-claims",
      await jsonRequest(
        "POST",
        { user_id: "bob", uid: "uid-bob", type: "STAMP" },
        staffJwt,
      ),
    );
    expect(ineligible.status).toBe(409);
    await expect(readJson(ineligible)).resolves.toMatchObject({ code: "PRIZE_NOT_ELIGIBLE" });
  });

  it("claims the stamp prize during the event after the live stamp threshold is met", async () => {
    const server = await createTestServer();
    const alice = await initializeUser(server, "alice");
    await pairTag(server, alice.headers, "uid-alice");

    for (let index = 0; index < 25; index += 1) {
      const sponsorId = `sponsor-${index}`;
      await initializeUser(server, sponsorId, "SPONSOR");
      await server.db
        .prepare(
          `
          INSERT INTO collections (scanner_user_id, collected_user_id)
          VALUES (?1, ?2)
          `,
        )
        .bind("alice", sponsorId)
        .run();
    }

    const staffJwt = await authHeaders("staff", "STAFF");
    const claim = await server.request(
      "/staff/prize-claims",
      await jsonRequest(
        "POST",
        { user_id: "alice", uid: "uid-alice", type: "STAMP" },
        staffJwt,
      ),
    );
    expect(claim.status).toBe(200);
    await expect(readJson(claim)).resolves.toMatchObject({
      data: { type: "STAMP", freeze_id: null, stamp_prize: true, rank_prize: false },
    });

    const status = await server.request("/staff/prize-claims/alice?type=STAMP", {
      headers: staffJwt,
    });
    await expect(readJson(status)).resolves.toMatchObject({
      data: { type: "STAMP", freeze_id: null, claimed: true },
    });
  });
});
