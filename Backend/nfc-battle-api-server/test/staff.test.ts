import { describe, expect, it, vi } from "vitest";
import {
  authHeaders,
  createTestServer,
  initializeUser,
  jsonRequest,
  pairTag,
  readJson,
  scanTag,
  staffHeaders,
} from "./helpers";

describe("staff scoreboard edge cases", () => {
  it("rejects staff endpoints without a staff JWT", async () => {
    const server = await createTestServer();

    for (const [path, method] of [
      ["/staff/scoreboard_status", "GET"],
      ["/staff/replace_user_tag", "POST"],
      ["/staff/freeze_scoreboard", "POST"],
      ["/staff/resume_scoreboard", "POST"],
    ] as const) {
      const response = await server.request(path, { method });

      expect(response.status).toBe(401);
      await expect(readJson(response)).resolves.toMatchObject({
        code: "UNAUTHORIZED",
      });
    }
  });

  it("rejects staff endpoints for non-staff JWTs", async () => {
    const server = await createTestServer();
    const attendeeJwt = await authHeaders("attendee", "ATTENDEE");

    for (const [path, method] of [
      ["/staff/scoreboard_status", "GET"],
      ["/staff/replace_user_tag", "POST"],
      ["/staff/freeze_scoreboard", "POST"],
      ["/staff/resume_scoreboard", "POST"],
    ] as const) {
      const response = await server.request(path, { method, headers: attendeeJwt });

      expect(response.status).toBe(403);
      await expect(readJson(response)).resolves.toMatchObject({
        code: "FORBIDDEN",
      });
    }
  });

  it("rejects danger-token staff endpoints without the staff danger token", async () => {
    const server = await createTestServer();
    const staffJwt = await authHeaders("staff", "STAFF");

    for (const [path, method] of [
      ["/staff/scoreboard_status", "GET"],
      ["/staff/freeze_scoreboard", "POST"],
      ["/staff/resume_scoreboard", "POST"],
    ] as const) {
      const response = await server.request(path, { method, headers: staffJwt });

      expect(response.status).toBe(401);
      await expect(readJson(response)).resolves.toMatchObject({
        code: "STAFF_DANGER_TOKEN_INVALID",
      });
    }
  });

  it("requires a staff JWT for replacing a user's NFC tag", async () => {
    const server = await createTestServer();

    const missingJwt = await server.request("/staff/replace_user_tag", { method: "POST" });
    expect(missingJwt.status).toBe(401);
    await expect(readJson(missingJwt)).resolves.toMatchObject({
      code: "UNAUTHORIZED",
    });

    const attendeeJwt = await server.request(
      "/staff/replace_user_tag",
      await jsonRequest(
        "POST",
        {
          user_id: "alice",
          new_physical_id: "tag-alice",
        },
        await authHeaders("attendee", "ATTENDEE"),
      ),
    );
    expect(attendeeJwt.status).toBe(403);
    await expect(readJson(attendeeJwt)).resolves.toMatchObject({
      code: "FORBIDDEN",
    });
  });

  it("replaces a user's NFC tag without changing profile or collection versions", async () => {
    const server = await createTestServer();
    const alice = await initializeUser(server, "alice");
    const bob = await initializeUser(server, "bob");
    const staffJwt = await authHeaders("staff", "STAFF");
    await pairTag(server, alice.headers, "tag-alice-old");

    const before = await readJson(await server.request("/users/me", { headers: alice.headers })) as {
      data: {
        physical_id: string;
        profile_version: number;
        collection_version: number;
      };
    };
    expect(before.data.physical_id).toBe("tag-alice-old");

    const update = await server.request(
      "/staff/replace_user_tag",
      await jsonRequest(
        "POST",
        {
          user_id: " alice ",
          new_physical_id: " tag-alice-new ",
        },
        staffJwt,
      ),
    );
    expect(update.status).toBe(200);

    await expect(
      server.db
        .prepare("SELECT user_id FROM nfc_tags WHERE physical_id = 'tag-alice-old'")
        .first<{ user_id: string }>(),
    ).resolves.toBeNull();
    await expect(
      server.db
        .prepare("SELECT physical_id FROM nfc_tags WHERE user_id = 'alice'")
        .first<{ physical_id: string }>(),
    ).resolves.toEqual({ physical_id: "tag-alice-new" });

    const oldTagScan = await scanTag(server, bob.headers, "alice", "tag-alice-old");
    expect(oldTagScan.status).toBe(403);
    await expect(readJson(oldTagScan)).resolves.toMatchObject({
      code: "PHYSICAL_ID_MISMATCH",
    });

    const newTagScan = await scanTag(server, bob.headers, "alice", "tag-alice-new");
    expect(newTagScan.status).toBe(200);

    const after = await readJson(await server.request("/users/me", { headers: alice.headers })) as {
      data: {
        physical_id: string;
        profile_version: number;
        collection_version: number;
      };
    };
    expect(after.data).toMatchObject({
      physical_id: "tag-alice-new",
      profile_version: before.data.profile_version,
      collection_version: before.data.collection_version,
    });

    const bootstrap = await readJson(
      await server.request("/users/me/bootstrap", { headers: alice.headers }),
    ) as {
      data: {
        me: {
          physical_id: string;
          nfc_tag_key: string;
        };
      };
    };
    expect(bootstrap.data.me.physical_id).toBe("tag-alice-new");
    expect(bootstrap.data.me.nfc_tag_key).toMatch(/^[0-9a-f]{12}$/);
  });

  it("allows a staff tag update when the new tag is already owned by the same user", async () => {
    const server = await createTestServer();
    const alice = await initializeUser(server, "alice");
    const staffJwt = await authHeaders("staff", "STAFF");
    await pairTag(server, alice.headers, "tag-alice");

    const update = await server.request(
      "/staff/replace_user_tag",
      await jsonRequest(
        "POST",
        {
          user_id: "alice",
          new_physical_id: "tag-alice",
        },
        staffJwt,
      ),
    );

    expect(update.status).toBe(200);
    await expect(
      server.db.prepare("SELECT COUNT(*) AS count FROM nfc_tags").first<{ count: number }>(),
    ).resolves.toEqual({ count: 1 });
  });

  it("rejects updating a user to another user's NFC tag", async () => {
    const server = await createTestServer();
    const alice = await initializeUser(server, "alice");
    const bob = await initializeUser(server, "bob");
    const staffJwt = await authHeaders("staff", "STAFF");
    await pairTag(server, alice.headers, "tag-alice");
    await pairTag(server, bob.headers, "tag-bob");

    const update = await server.request(
      "/staff/replace_user_tag",
      await jsonRequest(
        "POST",
        {
          user_id: "alice",
          new_physical_id: "tag-bob",
        },
        staffJwt,
      ),
    );

    expect(update.status).toBe(409);
    await expect(readJson(update)).resolves.toMatchObject({
      code: "TAG_ALREADY_PAIRED",
    });
    await expect(
      server.db
        .prepare("SELECT physical_id FROM nfc_tags WHERE user_id = 'alice'")
        .first<{ physical_id: string }>(),
    ).resolves.toEqual({ physical_id: "tag-alice" });
    await expect(
      server.db
        .prepare("SELECT physical_id FROM nfc_tags WHERE user_id = 'bob'")
        .first<{ physical_id: string }>(),
    ).resolves.toEqual({ physical_id: "tag-bob" });
  });

  it("rejects invalid or unknown staff tag update requests", async () => {
    const server = await createTestServer();
    const staffJwt = await authHeaders("staff", "STAFF");

    for (const body of [
      null,
      "nope",
      {},
      { user_id: "", new_physical_id: "tag-alice" },
      { user_id: "alice", new_physical_id: "" },
      { user_id: "alice", new_physical_id: "tag-alice", extra: true },
    ]) {
      const response = await server.request(
        "/staff/replace_user_tag",
        await jsonRequest("POST", body, staffJwt),
      );

      expect(response.status).toBe(400);
      await expect(readJson(response)).resolves.toMatchObject({
        code: "BAD_REQUEST",
      });
    }

    const unknownUser = await server.request(
      "/staff/replace_user_tag",
      await jsonRequest(
        "POST",
        {
          user_id: "missing",
          new_physical_id: "tag-missing",
        },
        staffJwt,
      ),
    );
    expect(unknownUser.status).toBe(404);
    await expect(readJson(unknownUser)).resolves.toMatchObject({
      code: "USER_NOT_FOUND",
    });
  });

  it("rejects resume while the scoreboard is open", async () => {
    const server = await createTestServer();

    const response = await server.request("/staff/resume_scoreboard", {
      method: "POST",
      headers: await staffDangerHeaders(),
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
      { scoring_cutoff_at: "9999-01-01T00:00:00Z" },
      { scoring_cutoff_at: "2026-04-12T15:00:00Z", extra: true },
    ]) {
      const response = await server.request(
        "/staff/freeze_scoreboard",
        await jsonRequest("POST", body, await staffDangerHeaders()),
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
      headers: await staffDangerHeaders(),
    });
    expect(firstFreeze.status).toBe(200);

    const secondFreeze = await server.request("/staff/freeze_scoreboard", {
      method: "POST",
      headers: await staffDangerHeaders(),
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
      headers: await staffDangerHeaders(),
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
      headers: await staffDangerHeaders(),
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
      headers: await staffDangerHeaders(),
    });
    expect(resume.status).toBe(200);

    const openStatus = await server.request("/staff/scoreboard_status", {
      headers: await staffDangerHeaders(),
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
        headers: await staffDangerHeaders(),
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
        headers: await staffDangerHeaders(),
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
        headers: await staffDangerHeaders(),
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
      headers: await staffDangerHeaders(),
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
      headers: await staffDangerHeaders(),
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
      headers: await staffDangerHeaders(),
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

async function staffDangerHeaders() {
  return {
    ...(await authHeaders("staff", "STAFF")),
    ...staffHeaders(),
  };
}
