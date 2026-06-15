import { describe, expect, it } from "vitest";
import { authHeaders, createTestServer, jsonRequest, pairTag, readJson } from "./helpers";

describe("tag pairing edge cases", () => {
  it("rejects unauthenticated pair requests", async () => {
    const server = await createTestServer();

    const response = await server.request(
      "/tags/pair",
      await jsonRequest("POST", { physical_id: "tag-alice" }),
    );

    expect(response.status).toBe(401);
    await expect(readJson(response)).resolves.toMatchObject({
      code: "UNAUTHORIZED",
    });
  });

  it("rejects invalid pair request bodies", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");

    for (const body of [
      {},
      { physical_id: "" },
      { physical_id: "tag-alice", extra: "nope" },
      { physical_id: 123 },
    ]) {
      const response = await server.request("/tags/pair", await jsonRequest("POST", body, aliceAuth));

      expect(response.status).toBe(400);
      await expect(readJson(response)).resolves.toMatchObject({
        code: "BAD_REQUEST",
      });
    }
  });

  it("rejects pair requests for users that have not been initialized", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");

    const response = await pairTag(server, aliceAuth, "tag-alice");

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
    expect((await pairTag(server, aliceAuth, "tag-alice")).status).toBe(200);

    const response = await pairTag(server, malloryAuth, "tag-alice");

    expect(response.status).toBe(404);
    await expect(readJson(response)).resolves.toMatchObject({
      code: "USER_NOT_FOUND",
    });
  });

  it("rejects pairing the same tag or pairing a user twice", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const bobAuth = await authHeaders("bob");
    await server.request("/users/me", { headers: aliceAuth });
    await server.request("/users/me", { headers: bobAuth });

    expect((await pairTag(server, aliceAuth, "tag-alice")).status).toBe(200);

    const sameTag = await pairTag(server, bobAuth, "tag-alice");
    expect(sameTag.status).toBe(409);
    await expect(readJson(sameTag)).resolves.toMatchObject({
      code: "TAG_ALREADY_PAIRED",
    });

    const sameUser = await pairTag(server, aliceAuth, "tag-alice-2");
    expect(sameUser.status).toBe(409);
    await expect(readJson(sameUser)).resolves.toMatchObject({
      code: "TAG_ALREADY_PAIRED",
    });

    await expect(
      server.db.prepare("SELECT COUNT(*) AS count FROM nfc_tags").first<{ count: number }>(),
    ).resolves.toEqual({ count: 1 });
  });
});
