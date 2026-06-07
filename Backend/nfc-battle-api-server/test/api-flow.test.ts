import { describe, expect, it } from "vitest";
import { authHeaders, createTestServer, jsonRequest, readJson, staffHeaders } from "./helpers";

describe("NFC Battle API flow", () => {
  it("supports profile, tag pairing, scan, missions, scoreboard, freeze, prize, and resume", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice", "ATTENDEE");
    const sponsorAuth = await authHeaders("sponsor-one", "SPONSOR");
    const communityAuth = await authHeaders("community-one", "COMMUNITY");

    const aliceProfileResponse = await server.request("/users/me", { headers: aliceAuth });
    expect(aliceProfileResponse.status).toBe(200);
    await expect(readJson(aliceProfileResponse)).resolves.toMatchObject({
      status: "success",
      data: {
        user_id: "alice",
        role: "ATTENDEE",
        physical_id: null,
        collection: [],
      },
    });

    const patchResponse = await server.request(
      "/users/me",
      await jsonRequest("PATCH", { display_name: "Alice", emoji_icon: "🙂" }, aliceAuth),
    );
    expect(patchResponse.status).toBe(200);
    await expect(readJson(patchResponse)).resolves.toMatchObject({
      data: {
        display_name: "Alice",
        emoji_icon: "🙂",
      },
    });

    await expect(pairTag(server, aliceAuth, "tag-alice")).resolves.toBe(200);
    await expect(pairTag(server, sponsorAuth, "tag-sponsor")).resolves.toBe(200);
    await expect(pairTag(server, communityAuth, "tag-community")).resolves.toBe(200);

    const duplicatePair = await server.request(
      "/tags/pair",
      await jsonRequest("POST", { physical_id: "tag-alice" }, await authHeaders("mallory")),
    );
    expect(duplicatePair.status).toBe(409);

    const lockedProfile = await server.request("/users/sponsor-one", { headers: aliceAuth });
    expect(lockedProfile.status).toBe(200);
    await expect(readJson(lockedProfile)).resolves.toEqual({
      status: "success",
      data: {
        user_id: "sponsor-one",
        display_name: "Player_sponsor-",
        emoji_icon: "🙂",
      },
    });

    const mismatchScan = await server.request(
      "/collection/scan",
      await jsonRequest(
        "POST",
        { user_id: "sponsor-one", physical_id: "tag-community" },
        aliceAuth,
      ),
    );
    expect(mismatchScan.status).toBe(403);

    const sponsorScan = await scanTag(server, aliceAuth, "sponsor-one", "tag-sponsor");
    expect(sponsorScan.status).toBe(200);
    await expect(readJson(sponsorScan)).resolves.toEqual({
      status: "success",
      data: {
        collected_user_id: "sponsor-one",
        first_time_collected: true,
      },
    });

    const duplicateScan = await scanTag(server, aliceAuth, "sponsor-one", "tag-sponsor");
    expect(duplicateScan.status).toBe(200);
    await expect(readJson(duplicateScan)).resolves.toMatchObject({
      data: {
        first_time_collected: false,
      },
    });

    await scanTag(server, aliceAuth, "community-one", "tag-community");

    const unlockedProfile = await server.request("/users/sponsor-one?physical_id=tag-sponsor", {
      headers: aliceAuth,
    });
    expect(unlockedProfile.status).toBe(200);
    await expect(readJson(unlockedProfile)).resolves.toMatchObject({
      data: {
        user_id: "sponsor-one",
        role: "SPONSOR",
        physical_id: "tag-sponsor",
        collection: [],
      },
    });

    const stampMission = await server.request("/missions/stamp", { headers: aliceAuth });
    expect(stampMission.status).toBe(200);
    await expect(readJson(stampMission)).resolves.toMatchObject({
      data: {
        stamp_threshold: 10,
        sponsor_count: 1,
        community_count: 1,
        eligible_for_stamp_prize: false,
      },
    });

    const scoreboard = await server.request("/scoreboard?limit=2", { headers: aliceAuth });
    expect(scoreboard.status).toBe(200);
    const scoreboardBody = await readJson(scoreboard) as {
      data: {
        offset: number;
        limit: number;
        frozen: boolean;
        rankings: Array<{ rank: number; user_id: string; score: number }>;
      };
    };
    expect(scoreboardBody.data).toMatchObject({
      offset: 0,
      limit: 2,
      frozen: false,
    });
    expect(scoreboardBody.data.rankings[0]).toMatchObject({
      rank: 1,
      user_id: "alice",
      score: 20,
    });

    const phishing = await server.request(
      "/collections/phishing",
      await jsonRequest("POST", { victim: "alice", attacker: "sponsor-one" }, aliceAuth),
    );
    expect(phishing.status).toBe(200);

    const prizeBeforeFreeze = await server.request("/users/me/prize", { headers: aliceAuth });
    expect(prizeBeforeFreeze.status).toBe(409);

    const statusBeforeFreeze = await server.request("/staff/scoreboard_status", {
      headers: staffHeaders(),
    });
    expect(statusBeforeFreeze.status).toBe(200);
    await expect(readJson(statusBeforeFreeze)).resolves.toMatchObject({
      data: {
        state: "OPEN",
        freeze_id: null,
        freezing_stale: false,
      },
    });

    const freeze = await server.request("/staff/freeze_scoreboard", {
      method: "POST",
      headers: staffHeaders(),
    });
    expect(freeze.status).toBe(200);
    await expect(readJson(freeze)).resolves.toMatchObject({
      data: {
        frozen: true,
        stamp_threshold: 10,
        rank_threshold: 10,
      },
    });

    const duplicateFreeze = await server.request("/staff/freeze_scoreboard", {
      method: "POST",
      headers: staffHeaders(),
    });
    expect(duplicateFreeze.status).toBe(409);

    const prize = await server.request("/users/me/prize", { headers: aliceAuth });
    expect(prize.status).toBe(200);
    await expect(readJson(prize)).resolves.toMatchObject({
      data: {
        scoreboard_frozen: true,
        stamp_prize: false,
        rank_prize: true,
        rank: 1,
      },
    });

    const resume = await server.request("/staff/resume_scoreboard", {
      method: "POST",
      headers: staffHeaders(),
    });
    expect(resume.status).toBe(200);

    const prizeAfterResume = await server.request("/users/me/prize", { headers: aliceAuth });
    expect(prizeAfterResume.status).toBe(409);
  });
});

async function pairTag(
  server: Awaited<ReturnType<typeof createTestServer>>,
  headers: Record<string, string>,
  physicalId: string,
) {
  const response = await server.request(
    "/tags/pair",
    await jsonRequest("POST", { physical_id: physicalId }, headers),
  );
  return response.status;
}

async function scanTag(
  server: Awaited<ReturnType<typeof createTestServer>>,
  headers: Record<string, string>,
  userId: string,
  physicalId: string,
) {
  return server.request(
    "/collection/scan",
    await jsonRequest("POST", { user_id: userId, physical_id: physicalId }, headers),
  );
}
