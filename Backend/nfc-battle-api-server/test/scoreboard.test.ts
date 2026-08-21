import { describe, expect, it } from "vitest";
import {
  authHeaders,
  createTestServer,
  jsonRequest,
  pairTag,
  readJson,
  refreshScoreboard,
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
        stamp_threshold: 20,
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
    await server.request("/users/me", { headers: carolAuth });
    expect((await pairTag(server, carolAuth, "04:00:00:00:00:00:04")).status).toBe(200);

    await scanTag(server, bobAuth, "carol", "04:00:00:00:00:00:04");
    await refreshScoreboard(server);

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
        display_name: "",
        emoji_icon: "🙂",
        score: 0,
        external_prize: false,
      },
      {
        rank: 3,
        user_id: "carol",
        display_name: "",
        emoji_icon: "🙂",
        score: 0,
        external_prize: false,
      },
    ]);
  });

  it("serves one stored live snapshot across users without recalculating it", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const bobAuth = await authHeaders("bob");
    const carolAuth = await authHeaders("carol");

    await server.request("/users/me", { headers: aliceAuth });
    await server.request("/users/me", { headers: bobAuth });
    await server.request("/users/me", { headers: carolAuth });
    expect((await pairTag(server, carolAuth, "04:00:00:00:00:00:04")).status).toBe(200);
    expect((await scanTag(server, bobAuth, "carol", "04:00:00:00:00:00:04")).status).toBe(200);

    const recordingDb = new QueryRecordingDb(server.db);
    server.env.DB = recordingDb as unknown as D1Database;
    await refreshScoreboard(server);

    const aliceResponse = await server.request("/scoreboard/me", { headers: aliceAuth });
    const bobResponse = await server.request("/scoreboard/me", { headers: bobAuth });

    expect(aliceResponse.status).toBe(200);
    await expect(readJson(aliceResponse)).resolves.toMatchObject({
      data: {
        rank: 2,
        score: 0,
        num_of_collection: 0,
        num_of_phishing: 0,
        score_per_collection: 10,
        phishing_penalty: 10,
        frozen: false,
        freeze_id: null,
        scoring_cutoff_at: null,
      },
    });
    expect(bobResponse.status).toBe(200);
    await expect(readJson(bobResponse)).resolves.toMatchObject({
      data: {
        rank: 1,
        score: 10,
        num_of_collection: 1,
        num_of_phishing: 0,
        score_per_collection: 10,
        phishing_penalty: 10,
        frozen: false,
        freeze_id: null,
        scoring_cutoff_at: null,
      },
    });
    expect(recordingDb.rankingQueryCount).toBe(1);
    expect(recordingDb.gameStateQueryCount).toBe(2);

    await server.db
      .prepare(
        `
        UPDATE game_state
        SET state = 'FREEZING', freeze_id = 'freeze_rank_cache_test'
        WHERE id = 1
        `,
      )
      .run();
    await refreshScoreboard(server);

    const freezing = await server.request("/scoreboard/me", { headers: aliceAuth });
    expect(freezing.status).toBe(409);
    await expect(readJson(freezing)).resolves.toMatchObject({ code: "SCOREBOARD_FREEZING" });
    expect(recordingDb.rankingQueryCount).toBe(1);
    expect(recordingDb.gameStateQueryCount).toBe(3);
  });

  it("applies the phishing penalty to live scores and ranks", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const bobAuth = await authHeaders("bob");
    const carolAuth = await authHeaders("carol");
    await server.request("/users/me", { headers: aliceAuth });
    await server.request("/users/me", { headers: bobAuth });
    await server.request("/users/me", { headers: carolAuth });
    expect((await pairTag(server, carolAuth, "04:00:00:00:00:00:04")).status).toBe(200);
    expect((await scanTag(server, aliceAuth, "carol", "04:00:00:00:00:00:04")).status).toBe(200);
    expect((await scanTag(server, bobAuth, "carol", "04:00:00:00:00:00:04")).status).toBe(200);

    const phishing = await server.request(
      "/collection/phishing",
      await jsonRequest("POST", { victim: "alice", attacker: "bob" }, aliceAuth),
    );
    expect(phishing.status).toBe(200);
    await refreshScoreboard(server);

    const response = await server.request("/scoreboard?limit=2", { headers: aliceAuth });
    expect(response.status).toBe(200);
    const body = await readJson(response) as {
      data: { rankings: Array<{ rank: number; user_id: string; score: number }> };
    };
    expect(body.data.rankings).toMatchObject([
      { rank: 1, user_id: "bob", score: 10 },
      { rank: 2, user_id: "alice", score: 0 },
    ]);

    const myScore = await server.request("/scoreboard/me", { headers: aliceAuth });
    expect(myScore.status).toBe(200);
    await expect(readJson(myScore)).resolves.toMatchObject({
      data: {
        rank: 2,
        score: 0,
        num_of_collection: 1,
        num_of_phishing: 1,
        score_per_collection: 10,
        phishing_penalty: 10,
        frozen: false,
      },
    });
  });

  it("serves arbitrary pages from one stored snapshot", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const bobAuth = await authHeaders("bob");
    await server.request("/users/me", { headers: aliceAuth });
    await server.request("/users/me", { headers: bobAuth });

    const recordingDb = new QueryRecordingDb(server.db);
    server.env.DB = recordingDb as unknown as D1Database;
    await refreshScoreboard(server);

    const first = await server.request("/scoreboard?offset=0&limit=2", { headers: aliceAuth });
    const second = await server.request("/scoreboard?offset=0&limit=2", { headers: bobAuth });
    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect(await readJson(second)).toEqual(await readJson(first));
    expect(recordingDb.rankingQueryCount).toBe(1);
    expect(recordingDb.gameStateQueryCount).toBe(2);

    const differentPage = await server.request("/scoreboard?offset=0&limit=1", {
      headers: aliceAuth,
    });
    expect(differentPage.status).toBe(200);
    expect(recordingDb.rankingQueryCount).toBe(1);

    await server.db
      .prepare(
        `
        UPDATE game_state
        SET state = 'FREEZING', freeze_id = 'freeze_cache_test'
        WHERE id = 1
        `,
      )
      .run();
    await refreshScoreboard(server);

    const freezing = await server.request("/scoreboard?offset=0&limit=2", {
      headers: aliceAuth,
    });
    expect(freezing.status).toBe(409);
    await expect(readJson(freezing)).resolves.toMatchObject({ code: "SCOREBOARD_FREEZING" });
    expect(recordingDb.rankingQueryCount).toBe(1);
  });

  it("returns a retryable error until the first snapshot is published", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    await server.request("/users/me", { headers: aliceAuth });

    const unavailable = await server.request("/scoreboard", { headers: aliceAuth });
    expect(unavailable.status).toBe(409);
    await expect(readJson(unavailable)).resolves.toMatchObject({
      code: "SCOREBOARD_READ_INCONSISTENT",
    });

    await refreshScoreboard(server);
    expect((await server.request("/scoreboard", { headers: aliceAuth })).status).toBe(200);
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
    await server.request("/users/me", { headers: bobAuth });
    await server.request("/users/me", { headers: carolAuth });
    await server.request("/users/me", { headers: daveAuth });
    expect((await pairTag(server, bobAuth, "04:00:00:00:00:00:03")).status).toBe(200);
    expect((await pairTag(server, carolAuth, "04:00:00:00:00:00:04")).status).toBe(200);
    expect((await pairTag(server, daveAuth, "04:00:00:00:00:00:05")).status).toBe(200);

    expect((await scanTag(server, aliceAuth, "bob", "04:00:00:00:00:00:03")).status).toBe(200);
    expect((await scanTag(server, aliceAuth, "carol", "04:00:00:00:00:00:04")).status).toBe(200);
    expect((await scanTag(server, aliceAuth, "dave", "04:00:00:00:00:00:05")).status).toBe(200);

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

    for (let index = 0; index < 20; index += 1) {
      const sponsorId = `post-freeze-sponsor-${index}`;
      const sponsorTagId = `04:00:00:00:00:01:${index.toString(16).toUpperCase().padStart(2, "0")}`;
      const sponsorAuth = await authHeaders(sponsorId, "SPONSOR");
      await server.request("/users/me", { headers: sponsorAuth });
      expect((await pairTag(server, sponsorAuth, sponsorTagId)).status).toBe(200);
      expect((await scanTag(server, aliceAuth, sponsorId, sponsorTagId)).status).toBe(200);
    }

    const liveMission = await server.request("/missions/stamp", { headers: aliceAuth });
    expect(liveMission.status).toBe(200);
    await expect(readJson(liveMission)).resolves.toMatchObject({
      data: {
        sponsor_count: 20,
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

    const myFrozenScore = await server.request("/scoreboard/me", { headers: aliceAuth });
    expect(myFrozenScore.status).toBe(200);
    await expect(readJson(myFrozenScore)).resolves.toMatchObject({
      data: {
        rank: 1,
        score: 0,
        num_of_collection: 1,
        num_of_phishing: 1,
        score_per_collection: 10,
        phishing_penalty: 10,
        frozen: true,
        freeze_id: freezeBody.data.freeze_id,
        scoring_cutoff_at: cutoff,
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
          scoring_cutoff_at = '2999-04-12T15:00:00.000Z'
        WHERE id = 1
        `,
      )
      .run();
    await refreshScoreboard(server);

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

class QueryRecordingDb {
  rankingQueryCount = 0;
  gameStateQueryCount = 0;

  constructor(private readonly db: D1Database) {}

  prepare(query: string) {
    if (query.includes("WITH collection_counts AS")) {
      this.rankingQueryCount += 1;
    }
    if (query.includes("FROM game_state")) {
      this.gameStateQueryCount += 1;
    }
    return this.db.prepare(query);
  }

  exec(query: string) {
    return this.db.exec(query);
  }
}
