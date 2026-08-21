import { describe, expect, it } from "vitest";
import { authHeaders, createTestServer, jsonRequest, pairTag, readJson } from "./helpers";

describe("tag pairing edge cases", () => {
  it("rejects unauthenticated pair requests", async () => {
    const server = await createTestServer();

    const response = await server.request(
      "/tags/pair",
      await jsonRequest("POST", { physical_id: "04:00:00:00:00:00:01" }),
    );

    expect(response.status).toBe(401);
    await expect(readJson(response)).resolves.toMatchObject({
      code: "UNAUTHORIZED",
    });
  });

  it("rejects invalid pair request bodies", async () => {
    const server = await createTestServer();

    const invalidBodies = [
      {},
      { physical_id: "" },
      { physical_id: "04:00:00:00:00:00" },
      { physical_id: "not-a-tag" },
      { physical_id: "04:00:00:00:00:00:01", extra: "nope" },
      { physical_id: 123 },
    ];

    for (const [index, body] of invalidBodies.entries()) {
      const auth = await authHeaders(`invalid-pair-${index}`);
      const response = await server.request("/tags/pair", await jsonRequest("POST", body, auth));

      expect(response.status).toBe(400);
      await expect(readJson(response)).resolves.toMatchObject({
        code: "BAD_REQUEST",
      });
    }
  });

  it("rejects pair requests for users that have not been initialized", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");

    const response = await pairTag(server, aliceAuth, "04:00:00:00:00:00:01");

    expect(response.status).toBe(404);
    await expect(readJson(response)).resolves.toMatchObject({
      code: "USER_NOT_FOUND",
    });
  });

  it("does not reveal paired tag state to users that have not been initialized", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const malloryAuth = await authHeaders("mallory");
    await server.request("/users/me", { headers: aliceAuth });
    expect((await pairTag(server, aliceAuth, "04:00:00:00:00:00:01")).status).toBe(200);

    const response = await pairTag(server, malloryAuth, "04:00:00:00:00:00:01");

    expect(response.status).toBe(404);
    await expect(readJson(response)).resolves.toMatchObject({
      code: "USER_NOT_FOUND",
    });
  });

  it("rejects a duplicate UID and prevents users from self-pairing additional UIDs", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const bobAuth = await authHeaders("bob");
    await server.request("/users/me", { headers: aliceAuth });
    await server.request("/users/me", { headers: bobAuth });

    expect((await pairTag(server, aliceAuth, "04:00:00:00:00:00:01")).status).toBe(200);

    const sameTag = await pairTag(server, bobAuth, "04:00:00:00:00:00:01");
    expect(sameTag.status).toBe(409);
    await expect(readJson(sameTag)).resolves.toMatchObject({
      code: "TAG_ALREADY_PAIRED",
    });

    const sameUser = await pairTag(server, aliceAuth, "04:00:00:00:00:00:02");
    expect(sameUser.status).toBe(409);
    await expect(readJson(sameUser)).resolves.toMatchObject({
      code: "TAG_ALREADY_PAIRED",
      message: "This user or NFC tag already has a pairing.",
    });

    await expect(
      server.db.prepare("SELECT COUNT(*) AS count FROM nfc_tags").first<{ count: number }>(),
    ).resolves.toEqual({ count: 1 });
  });
});
