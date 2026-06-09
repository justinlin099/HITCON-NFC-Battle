import { describe, expect, it } from "vitest";
import { authHeaders, createTestServer, pairTag, readJson, scanTag } from "./helpers";

describe("mission and scoreboard edge cases", () => {
  it("returns zero stamp progress for a newly initialized user", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");

    const response = await server.request("/missions/stamp", { headers: aliceAuth });

    expect(response.status).toBe(200);
    await expect(readJson(response)).resolves.toMatchObject({
      data: {
        stamp_threshold: 10,
        sponsor_count: 0,
        community_count: 0,
        eligible_for_stamp_prize: false,
      },
    });
  });

  it("rejects invalid scoreboard pagination", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");

    for (const query of [
      "offset=-1",
      "offset=1.5",
      "offset=abc",
      "limit=0",
      "limit=201",
      "limit=1.5",
      "limit=abc",
    ]) {
      const response = await server.request(`/scoreboard?${query}`, { headers: aliceAuth });

      expect(response.status).toBe(400);
      await expect(readJson(response)).resolves.toMatchObject({
        code: "BAD_REQUEST",
      });
    }
  });

  it("orders ties by user ID and respects offset/limit", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const bobAuth = await authHeaders("bob");
    const carolAuth = await authHeaders("carol");

    await server.request("/users/me", { headers: aliceAuth });
    await server.request("/users/me", { headers: bobAuth });
    expect((await pairTag(server, carolAuth, "tag-carol")).status).toBe(200);

    await scanTag(server, bobAuth, "carol", "tag-carol");

    const response = await server.request("/scoreboard?offset=1&limit=2", {
      headers: aliceAuth,
    });
    expect(response.status).toBe(200);

    const body = await readJson(response) as {
      data: {
        offset: number;
        limit: number;
        rankings: Array<{ rank: number; user_id: string; score: number }>;
      };
    };
    expect(body.data.offset).toBe(1);
    expect(body.data.limit).toBe(2);
    expect(body.data.rankings).toEqual([
      {
        rank: 2,
        user_id: "alice",
        display_name: "Player_alice",
        emoji_icon: "🙂",
        score: 0,
      },
      {
        rank: 3,
        user_id: "carol",
        display_name: "Player_carol",
        emoji_icon: "🙂",
        score: 0,
      },
    ]);
  });
});
