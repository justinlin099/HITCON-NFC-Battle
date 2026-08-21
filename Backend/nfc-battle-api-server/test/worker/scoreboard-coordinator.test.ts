import { env } from "cloudflare:workers";
import {
  evictDurableObject,
  runDurableObjectAlarm,
  runInDurableObject,
} from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { SCOREBOARD_COORDINATOR_NAME } from "../../src/scoreboard-coordinator-service";

describe("ScoreboardCoordinator", () => {
  it("publishes the first snapshot from its alarm", async () => {
    const coordinator = env.SCOREBOARD_COORDINATOR.getByName(SCOREBOARD_COORDINATOR_NAME);

    await expect(coordinator.readPage(0, 50)).resolves.toEqual({ status: "UNAVAILABLE" });
    await scheduleAndRunAlarm(coordinator);

    await expect(coordinator.readPage(0, 50)).resolves.toMatchObject({
      status: "READY",
      frozen: false,
      entries: [],
    });
    const nextAlarm = await runInDurableObject(coordinator, (_instance, state) => {
      return state.storage.getAlarm();
    });
    expect(nextAlarm).not.toBeNull();
    expect(nextAlarm).toBeGreaterThan(Date.now());
  });

  it("incrementally refreshes scores and preserves them across eviction", async () => {
    await insertUser("alice");
    await insertUser("bob");

    const coordinator = env.SCOREBOARD_COORDINATOR.getByName(SCOREBOARD_COORDINATOR_NAME);
    await coordinator.refreshNow();

    await env.DB.prepare(
      `
      INSERT INTO collections (scanner_user_id, collected_user_id)
      VALUES ('alice', 'bob')
      `,
    ).run();
    await env.DB.prepare(
      `
      INSERT INTO phishing_events (event_id, victim_user_id, attacker_user_id)
      VALUES ('phishing-1', 'bob', 'alice')
      `,
    ).run();

    await scheduleAndRunAlarm(coordinator);
    await expect(coordinator.readPage(0, 2)).resolves.toMatchObject({
      status: "READY",
      entries: [
        {
          rank: 1,
          user_id: "alice",
          score: 10,
          num_of_collection: 1,
          num_of_phishing: 0,
        },
        {
          rank: 2,
          user_id: "bob",
          score: -10,
          num_of_collection: 0,
          num_of_phishing: 1,
        },
      ],
    });

    await evictDurableObject(coordinator);
    const reloaded = env.SCOREBOARD_COORDINATOR.getByName(SCOREBOARD_COORDINATOR_NAME);
    await expect(reloaded.readUser("alice")).resolves.toMatchObject({
      status: "READY",
      entry: { rank: 1, score: 10 },
    });
  });

  it("publishes and preserves the frozen score snapshot, then resumes live scoring", async () => {
    await insertUser("alice");
    await insertUser("bob");
    await env.DB.prepare(
      `
      INSERT INTO collections (scanner_user_id, collected_user_id)
      VALUES ('alice', 'bob')
      `,
    ).run();

    const coordinator = env.SCOREBOARD_COORDINATOR.getByName(SCOREBOARD_COORDINATOR_NAME);
    await coordinator.refreshNow();

    const startedAt = new Date().toISOString();
    const freezeId = "freeze-worker-test";
    await expect(coordinator.freeze(freezeId, startedAt, startedAt)).resolves.toMatchObject({
      status: "FROZEN",
    });
    await expect(coordinator.readUser("alice")).resolves.toMatchObject({
      status: "READY",
      frozen: true,
      freeze_id: freezeId,
      entry: { score: 10 },
    });

    await expect(coordinator.resume()).resolves.toEqual({ status: "RESUMED" });
    await expect(coordinator.readUser("alice")).resolves.toMatchObject({
      status: "READY",
      frozen: false,
      freeze_id: null,
      entry: { score: 10 },
    });
  });
});

async function insertUser(userId: string) {
  await env.DB.prepare(
    `
    INSERT INTO users (user_id, display_name, role, emoji_icon)
    VALUES (?1, '', 'ATTENDEE', '🙂')
    `,
  ).bind(userId).run();
}

async function scheduleAndRunAlarm(coordinator: DurableObjectStub) {
  await runInDurableObject(coordinator, (_instance, state) => {
    return state.storage.setAlarm(Date.now() + 1_000);
  });
  expect(await runDurableObjectAlarm(coordinator)).toBe(true);
}
