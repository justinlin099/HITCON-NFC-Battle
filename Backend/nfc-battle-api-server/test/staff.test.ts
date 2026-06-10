import { describe, expect, it, vi } from "vitest";
import { authHeaders, createTestServer, jsonRequest, readJson, staffHeaders } from "./helpers";

describe("staff scoreboard edge cases", () => {
  it("rejects staff endpoints without the staff danger token", async () => {
    const server = await createTestServer();

    for (const [path, method] of [
      ["/staff/scoreboard_status", "GET"],
      ["/staff/freeze_scoreboard", "POST"],
      ["/staff/resume_scoreboard", "POST"],
    ] as const) {
      const response = await server.request(path, { method });

      expect(response.status).toBe(401);
      await expect(readJson(response)).resolves.toMatchObject({
        code: "STAFF_DANGER_TOKEN_INVALID",
      });
    }
  });

  it("rejects resume while the scoreboard is open", async () => {
    const server = await createTestServer();

    const response = await server.request("/staff/resume_scoreboard", {
      method: "POST",
      headers: staffHeaders(),
    });

    expect(response.status).toBe(409);
    await expect(readJson(response)).resolves.toMatchObject({
      code: "SCOREBOARD_NOT_FROZEN",
    });
  });

  it("rejects invalid freeze request bodies before changing scoreboard state", async () => {
    const server = await createTestServer();

    for (const body of [
      null,
      "nope",
      { scoring_cutoff_at: "not-a-date" },
      { scoring_cutoff_at: "2026-04-12T15:00:00Z", extra: true },
    ]) {
      const response = await server.request(
        "/staff/freeze_scoreboard",
        await jsonRequest("POST", body, staffHeaders()),
      );

      expect(response.status).toBe(400);
      await expect(readJson(response)).resolves.toMatchObject({
        code: "BAD_REQUEST",
      });
      await expect(
        server.db.prepare("SELECT state, freeze_id FROM game_state WHERE id = 1").first(),
      ).resolves.toEqual({
        state: "OPEN",
        freeze_id: null,
      });
    }
  });

  it("rejects a second freeze after the scoreboard is frozen", async () => {
    const server = await createTestServer();
    await server.request("/users/me", { headers: await authHeaders("alice") });

    const firstFreeze = await server.request("/staff/freeze_scoreboard", {
      method: "POST",
      headers: staffHeaders(),
    });
    expect(firstFreeze.status).toBe(200);

    const secondFreeze = await server.request("/staff/freeze_scoreboard", {
      method: "POST",
      headers: staffHeaders(),
    });
    expect(secondFreeze.status).toBe(409);
    await expect(readJson(secondFreeze)).resolves.toMatchObject({
      code: "SCOREBOARD_ALREADY_FROZEN",
    });
  });

  it("shows frozen status after freeze and open status after resume", async () => {
    const server = await createTestServer();
    await server.request("/users/me", { headers: await authHeaders("alice") });

    const freeze = await server.request("/staff/freeze_scoreboard", {
      method: "POST",
      headers: staffHeaders(),
    });
    expect(freeze.status).toBe(200);
    const freezeBody = await readJson(freeze) as {
      data: {
        freeze_id: string;
        scoring_cutoff_at: string;
        frozen_at: string;
      };
    };
    expect(freezeBody.data.freeze_id).toMatch(/^freeze_/);
    expect(freezeBody.data.scoring_cutoff_at).toEqual(expect.any(String));
    expect(freezeBody.data.frozen_at).toEqual(expect.any(String));

    const frozenStatus = await server.request("/staff/scoreboard_status", {
      headers: staffHeaders(),
    });
    expect(frozenStatus.status).toBe(200);
    await expect(readJson(frozenStatus)).resolves.toMatchObject({
      data: {
        state: "FROZEN",
        freeze_id: freezeBody.data.freeze_id,
        scoring_cutoff_at: freezeBody.data.scoring_cutoff_at,
        frozen_at: freezeBody.data.frozen_at,
        freeze_timeout_seconds: 30,
        freezing_stale: false,
      },
    });

    const resume = await server.request("/staff/resume_scoreboard", {
      method: "POST",
      headers: staffHeaders(),
    });
    expect(resume.status).toBe(200);

    const openStatus = await server.request("/staff/scoreboard_status", {
      headers: staffHeaders(),
    });
    expect(openStatus.status).toBe(200);
    await expect(readJson(openStatus)).resolves.toMatchObject({
      data: {
        state: "OPEN",
        freeze_id: null,
        freeze_started_at: null,
        scoring_cutoff_at: null,
        frozen_at: null,
        freezing_stale: false,
      },
    });
  });

  it("rolls back FREEZING state when freeze calculation fails", async () => {
    const server = await createTestServer();
    await server.request("/users/me", { headers: await authHeaders("alice") });
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => undefined);

    try {
      await server.db.exec(
        `
        CREATE TRIGGER fail_freeze_snapshot
        BEFORE INSERT ON prize_results
        BEGIN
          SELECT RAISE(ABORT, 'forced freeze failure');
        END;
        `,
      );

      const failedFreeze = await server.request("/staff/freeze_scoreboard", {
        method: "POST",
        headers: staffHeaders(),
      });
      expect(failedFreeze.status).toBe(400);
      expect(consoleError).toHaveBeenCalledWith("Failed to freeze scoreboard.", expect.any(Error));

      await expect(
        server.db
          .prepare("SELECT state, freeze_id, scoring_cutoff_at FROM game_state WHERE id = 1")
          .first(),
      ).resolves.toEqual({
        state: "OPEN",
        freeze_id: null,
        scoring_cutoff_at: null,
      });
      await expect(
        server.db.prepare("SELECT COUNT(*) AS count FROM prize_results").first<{ count: number }>(),
      ).resolves.toEqual({ count: 0 });

      await server.db.exec("DROP TRIGGER fail_freeze_snapshot");

      const retryFreeze = await server.request("/staff/freeze_scoreboard", {
        method: "POST",
        headers: staffHeaders(),
      });
      expect(retryFreeze.status).toBe(200);
    } finally {
      consoleError.mockRestore();
    }
  });

  it("fails freeze when the final FROZEN transition does not persist", async () => {
    const server = await createTestServer();
    await server.request("/users/me", { headers: await authHeaders("alice") });
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => undefined);

    try {
      await server.db.exec(
        `
        CREATE TRIGGER reset_freeze_before_frozen_transition
        AFTER INSERT ON prize_results
        BEGIN
          UPDATE game_state
          SET
            state = 'OPEN',
            freeze_id = NULL,
            freeze_started_at = NULL,
            scoring_cutoff_at = NULL,
            frozen_at = NULL
          WHERE id = 1;
        END;
        `,
      );

      const failedFreeze = await server.request("/staff/freeze_scoreboard", {
        method: "POST",
        headers: staffHeaders(),
      });
      expect(failedFreeze.status).toBe(400);
      expect(consoleError).toHaveBeenCalledWith("Failed to freeze scoreboard.", expect.any(Error));

      await expect(
        server.db
          .prepare("SELECT state, freeze_id, frozen_at FROM game_state WHERE id = 1")
          .first(),
      ).resolves.toEqual({
        state: "OPEN",
        freeze_id: null,
        frozen_at: null,
      });
      await expect(
        server.db.prepare("SELECT COUNT(*) AS count FROM prize_results").first<{ count: number }>(),
      ).resolves.toEqual({ count: 0 });
    } finally {
      await server.db.exec("DROP TRIGGER IF EXISTS reset_freeze_before_frozen_transition");
      consoleError.mockRestore();
    }
  });

  it("recovers stale FREEZING state and clears partial snapshot data", async () => {
    const server = await createTestServer();
    await server.request("/users/me", { headers: await authHeaders("alice") });

    await server.db.prepare(
      `
      UPDATE game_state
      SET
        state = 'FREEZING',
        freeze_id = 'freeze_stale',
        freeze_started_at = '2026-04-12T15:00:00.000Z',
        scoring_cutoff_at = '2026-04-12T15:00:00.000Z',
        frozen_at = NULL,
        freeze_timeout_seconds = 1
      WHERE id = 1
      `,
    ).run();
    await server.db.prepare(
      `
      INSERT INTO prize_results (
        freeze_id,
        user_id,
        final_score,
        rank,
        stamp_prize,
        rank_prize
      )
      VALUES ('freeze_stale', 'alice', 100, 1, 0, 1)
      `,
    ).run();
    await server.db.prepare(
      `
      INSERT INTO phishing_events (
        event_id,
        victim_user_id,
        attacker_user_id,
        applied_freeze_id
      )
      VALUES ('phishing_stale', 'alice', 'alice', 'freeze_stale')
      `,
    ).run();

    const staleStatus = await server.request("/staff/scoreboard_status", {
      headers: staffHeaders(),
    });
    expect(staleStatus.status).toBe(200);
    await expect(readJson(staleStatus)).resolves.toMatchObject({
      data: {
        state: "FREEZING",
        freeze_id: "freeze_stale",
        scoring_cutoff_at: "2026-04-12T15:00:00.000Z",
        freezing_stale: true,
      },
    });

    const resume = await server.request("/staff/resume_scoreboard", {
      method: "POST",
      headers: staffHeaders(),
    });
    expect(resume.status).toBe(200);

    await expect(
      server.db
        .prepare("SELECT COUNT(*) AS count FROM prize_results WHERE freeze_id = 'freeze_stale'")
        .first<{ count: number }>(),
    ).resolves.toEqual({ count: 0 });
    await expect(
      server.db
        .prepare("SELECT applied_freeze_id FROM phishing_events WHERE event_id = 'phishing_stale'")
        .first<{ applied_freeze_id: string | null }>(),
    ).resolves.toEqual({ applied_freeze_id: null });

    const openStatus = await server.request("/staff/scoreboard_status", {
      headers: staffHeaders(),
    });
    await expect(readJson(openStatus)).resolves.toMatchObject({
      data: {
        state: "OPEN",
        freeze_id: null,
        scoring_cutoff_at: null,
      },
    });
  });
});
