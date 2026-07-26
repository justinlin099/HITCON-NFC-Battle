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
    await pairTag(server, alice.headers, "uid-alice");
    await pairTag(server, bob.headers, "uid-bob");

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

    const staffJwt = await authHeaders("staff", "STAFF");
    const claimAlice = async () => server.request(
      "/staff/prize-claims",
      await jsonRequest("POST", { user_id: "alice", uid: "uid-alice" }, staffJwt),
    );
    expect((await claimAlice()).status).toBe(200);

    const duplicate = await claimAlice();
    expect(duplicate.status).toBe(409);
    await expect(readJson(duplicate)).resolves.toMatchObject({ code: "PRIZE_ALREADY_CLAIMED" });

    const ineligible = await server.request(
      "/staff/prize-claims",
      await jsonRequest("POST", { user_id: "bob", uid: "uid-bob" }, staffJwt),
    );
    expect(ineligible.status).toBe(409);
    await expect(readJson(ineligible)).resolves.toMatchObject({ code: "PRIZE_NOT_ELIGIBLE" });
  });
});
