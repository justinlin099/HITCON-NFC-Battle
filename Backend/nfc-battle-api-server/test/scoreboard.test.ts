import { describe, expect, it } from "vitest";
import {
  authHeaders,
  createTestServer,
  jsonRequest,
  pairTag,
  readJson,
  scanTag,
  staffHeaders,
} from "./helpers";

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

  it("uses the freeze cutoff and keeps frozen scoreboard and prize snapshots immutable", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const bobAuth = await authHeaders("bob");
    const carolAuth = await authHeaders("carol");
    const daveAuth = await authHeaders("dave");
    const staffDanger = await staffDangerHeaders();
    const cutoff = "2026-04-12T15:00:00.000Z";

    await server.request("/users/me", { headers: aliceAuth });
    expect((await pairTag(server, bobAuth, "tag-bob")).status).toBe(200);
    expect((await pairTag(server, carolAuth, "tag-carol")).status).toBe(200);
    expect((await pairTag(server, daveAuth, "tag-dave")).status).toBe(200);

    expect((await scanTag(server, aliceAuth, "bob", "tag-bob")).status).toBe(200);
    expect((await scanTag(server, aliceAuth, "carol", "tag-carol")).status).toBe(200);
    expect((await scanTag(server, aliceAuth, "dave", "tag-dave")).status).toBe(200);

    await server.db
      .prepare(
        `
        UPDATE collections
        SET first_collected_at = CASE collected_user_id
          WHEN 'bob' THEN '2026-04-12T14:59:00.000Z'
          WHEN 'carol' THEN '2026-04-12T15:01:00.000Z'
          WHEN 'dave' THEN '2026-04-12T15:02:00.000Z'
        END
        WHERE scanner_user_id = 'alice'
        `,
      )
      .run();

    await server.db
      .prepare(
        `
        INSERT INTO phishing_events (
          event_id,
          victim_user_id,
          attacker_user_id,
          created_at
        )
        VALUES
          ('phish-before-cutoff', 'alice', 'bob', '2026-04-12T14:58:00.000Z'),
          ('phish-after-cutoff', 'alice', 'bob', '2026-04-12T15:03:00.000Z')
        `,
      )
      .run();

    const freeze = await server.request(
      "/staff/freeze_scoreboard",
      await jsonRequest("POST", { scoring_cutoff_at: cutoff }, staffDanger),
    );
    expect(freeze.status).toBe(200);
    const freezeBody = await readJson(freeze) as {
      data: { freeze_id: string; scoring_cutoff_at: string };
    };
    expect(freezeBody.data.scoring_cutoff_at).toBe(cutoff);

    const scoreboard = await server.request("/scoreboard?limit=1", { headers: aliceAuth });
    expect(scoreboard.status).toBe(200);
    const frozenScoreboardBody = await readJson(scoreboard) as {
      data: {
        frozen: boolean;
        freeze_id: string;
        scoring_cutoff_at: string;
        rankings: Array<{ user_id: string; score: number }>;
      };
    };
    expect(frozenScoreboardBody.data).toMatchObject({
      frozen: true,
      freeze_id: freezeBody.data.freeze_id,
      scoring_cutoff_at: cutoff,
    });
    expect(frozenScoreboardBody.data.rankings[0]).toMatchObject({
      user_id: "alice",
      score: 0,
    });

    await expect(
      server.db
        .prepare(
          `
          SELECT event_id, applied_freeze_id
          FROM phishing_events
          ORDER BY event_id ASC
          `,
        )
        .all<{ event_id: string; applied_freeze_id: string | null }>(),
    ).resolves.toMatchObject({
      results: [
        {
          event_id: "phish-after-cutoff",
          applied_freeze_id: null,
        },
        {
          event_id: "phish-before-cutoff",
          applied_freeze_id: freezeBody.data.freeze_id,
        },
      ],
    });

    const prizeBeforeLiveChanges = await server.request("/users/me/prize", { headers: aliceAuth });
    expect(prizeBeforeLiveChanges.status).toBe(200);
    await expect(readJson(prizeBeforeLiveChanges)).resolves.toMatchObject({
      data: {
        stamp_prize: false,
        rank_prize: true,
        rank: 1,
      },
    });

    for (let index = 0; index < 10; index += 1) {
      const sponsorId = `post-freeze-sponsor-${index}`;
      const sponsorAuth = await authHeaders(sponsorId, "SPONSOR");
      expect((await pairTag(server, sponsorAuth, `tag-${sponsorId}`)).status).toBe(200);
      expect((await scanTag(server, aliceAuth, sponsorId, `tag-${sponsorId}`)).status).toBe(200);
    }

    const liveMission = await server.request("/missions/stamp", { headers: aliceAuth });
    expect(liveMission.status).toBe(200);
    await expect(readJson(liveMission)).resolves.toMatchObject({
      data: {
        sponsor_count: 10,
        community_count: 0,
        eligible_for_stamp_prize: true,
      },
    });

    const scoreboardAfterLiveChanges = await server.request("/scoreboard?limit=1", {
      headers: aliceAuth,
    });
    expect(scoreboardAfterLiveChanges.status).toBe(200);
    await expect(readJson(scoreboardAfterLiveChanges)).resolves.toMatchObject({
      data: {
        frozen: true,
        freeze_id: freezeBody.data.freeze_id,
        scoring_cutoff_at: cutoff,
        rankings: [
          {
            user_id: "alice",
            score: 0,
          },
        ],
      },
    });

    const prizeAfterLiveChanges = await server.request("/users/me/prize", { headers: aliceAuth });
    expect(prizeAfterLiveChanges.status).toBe(200);
    await expect(readJson(prizeAfterLiveChanges)).resolves.toMatchObject({
      data: {
        stamp_prize: false,
        rank_prize: true,
        rank: 1,
      },
    });
  });

  it("rejects scoreboard reads while a freeze is in progress", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    await server.request("/users/me", { headers: aliceAuth });

    await server.db
      .prepare(
        `
        UPDATE game_state
        SET
          state = 'FREEZING',
          freeze_id = 'freeze_in_progress',
          freeze_started_at = '2026-04-12T15:00:00.000Z',
          scoring_cutoff_at = '2026-04-12T15:00:00.000Z'
        WHERE id = 1
        `,
      )
      .run();

    const response = await server.request("/scoreboard", { headers: aliceAuth });

    expect(response.status).toBe(409);
    await expect(readJson(response)).resolves.toMatchObject({
      code: "SCOREBOARD_FREEZING",
    });
  });
});

async function staffDangerHeaders() {
  return {
    ...(await authHeaders("staff", "STAFF")),
    ...staffHeaders(),
  };
}
