import { describe, expect, it } from "vitest";
import {
  authHeaders,
  createTestServer,
  initializeUser,
  jsonRequest,
  pairTag,
  readJson,
  scanTag,
} from "./helpers";

describe("multiple NFC UIDs and staff unlock codes", () => {
  it("uses every paired UID for scans and returns one shared unlock code", async () => {
    const server = await createTestServer();
    const alice = await initializeUser(server, "alice");
    const bob = await initializeUser(server, "bob");
    const staffJwt = await authHeaders("staff", "STAFF");
    expect((await pairTag(server, alice.headers, "04:00:00:00:00:00:0D")).status).toBe(200);
    const additionalTag = await server.request(
      "/staff/pair_user_tag",
      await jsonRequest(
        "POST",
        { user_id: "alice", physical_id: "04:00:00:00:00:00:0E" },
        staffJwt,
      ),
    );
    expect(additionalTag.status).toBe(200);

    const aliceProfile = await readJson(await server.request("/users/me", { headers: alice.headers })) as {
      data: { physical_id: string; nfc_tag_key: string };
    };
    expect(aliceProfile.data.physical_id).toBe("04:00:00:00:00:00:0D");
    expect((await scanTag(server, bob.headers, "alice", "04:00:00:00:00:00:0E")).status).toBe(200);

    const recordingDb = new QueryRecordingDb(server.db);
    server.env.DB = recordingDb as unknown as D1Database;

    const unlock = await server.request(
      "/staff/nfc-unlock-code",
      await jsonRequest(
        "POST",
        { user_id: "alice", uid: "04:00:00:00:00:00:0E" },
        staffJwt,
      ),
    );
    expect(unlock.status).toBe(200);
    await expect(readJson(unlock)).resolves.toMatchObject({
      data: { user_id: "alice", uid: "04:00:00:00:00:00:0E", unlock_code: aliceProfile.data.nfc_tag_key },
    });
    expect(recordingDb.queries).toHaveLength(1);
    expect(recordingDb.queries[0]).toContain("SELECT nfc_tag_key FROM users");
    expect(recordingDb.queries[0]).not.toContain("nfc_tags");
    expect(recordingDb.queries[0]).not.toContain("collections");
  });

  it("repairs a missing unlock code without loading profile-related data", async () => {
    const server = await createTestServer();
    await initializeUser(server, "alice");
    await server.db.prepare("UPDATE users SET nfc_tag_key = NULL WHERE user_id = 'alice'").run();

    const unlock = await server.request(
      "/staff/nfc-unlock-code",
      await jsonRequest(
        "POST",
        { user_id: "alice", uid: "04:00:00:00:00:00:0C" },
        await authHeaders("staff", "STAFF"),
      ),
    );

    expect(unlock.status).toBe(200);
    const body = (await readJson(unlock)) as { data: { unlock_code: string } };
    expect(body.data.unlock_code).toMatch(/^[0-9a-f]{12}$/);
    await expect(
      server.db
        .prepare("SELECT nfc_tag_key FROM users WHERE user_id = 'alice'")
        .first<{ nfc_tag_key: string }>(),
    ).resolves.toEqual({ nfc_tag_key: body.data.unlock_code });
  });
});

class QueryRecordingDb {
  readonly queries: string[] = [];

  constructor(private readonly db: D1Database) {}

  prepare(query: string) {
    this.queries.push(query);
    return this.db.prepare(query);
  }

  exec(query: string) {
    return this.db.exec(query);
  }
}
