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
    await pairTag(server, alice.headers, "uid-alice-one");
    await pairTag(server, alice.headers, "uid-alice-two");

    const aliceProfile = await readJson(await server.request("/users/me", { headers: alice.headers })) as {
      data: { physical_ids: string[]; nfc_tag_key: string };
    };
    expect(aliceProfile.data.physical_ids).toEqual(["uid-alice-one", "uid-alice-two"]);
    expect((await scanTag(server, bob.headers, "alice", "uid-alice-two")).status).toBe(200);

    const unlock = await server.request(
      "/staff/nfc-unlock-code",
      await jsonRequest(
        "POST",
        { user_id: "alice", uid: "uid-alice-two" },
        await authHeaders("staff", "STAFF"),
      ),
    );
    expect(unlock.status).toBe(200);
    await expect(readJson(unlock)).resolves.toMatchObject({
      data: { user_id: "alice", uid: "uid-alice-two", unlock_code: aliceProfile.data.nfc_tag_key },
    });
  });
});
