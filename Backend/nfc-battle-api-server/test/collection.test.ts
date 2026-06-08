import { describe, expect, it } from "vitest";
import { authHeaders, createTestServer, jsonRequest, pairTag, readJson, scanTag } from "./helpers";

describe("collection scan edge cases", () => {
  it("rejects unauthenticated scan requests", async () => {
    const server = await createTestServer();

    const response = await server.request(
      "/collection/scan",
      await jsonRequest("POST", { user_id: "bob", physical_id: "tag-bob" }),
    );

    expect(response.status).toBe(401);
    await expect(readJson(response)).resolves.toMatchObject({
      code: "UNAUTHORIZED",
    });
  });

  it("rejects invalid scan request bodies", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");

    for (const body of [
      {},
      { user_id: "bob" },
      { physical_id: "tag-bob" },
      { user_id: "", physical_id: "tag-bob" },
      { user_id: "bob", physical_id: "" },
      { user_id: "bob", physical_id: "tag-bob", extra: "nope" },
    ]) {
      const response = await server.request(
        "/collection/scan",
        await jsonRequest("POST", body, aliceAuth),
      );

      expect(response.status).toBe(400);
      await expect(readJson(response)).resolves.toMatchObject({
        code: "BAD_REQUEST",
      });
    }
  });

  it("rejects self scan before checking the tag", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");

    const response = await scanTag(server, aliceAuth, "alice", "tag-alice");

    expect(response.status).toBe(400);
    await expect(readJson(response)).resolves.toMatchObject({
      code: "BAD_REQUEST",
    });
  });

  it("rejects unknown target users", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");

    const response = await scanTag(server, aliceAuth, "bob", "tag-bob");

    expect(response.status).toBe(404);
    await expect(readJson(response)).resolves.toMatchObject({
      code: "USER_NOT_FOUND",
    });
  });

  it("rejects unpaired or mismatched physical IDs", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const bobAuth = await authHeaders("bob");
    const carolAuth = await authHeaders("carol");

    await server.request("/users/me", { headers: bobAuth });
    await server.request("/users/me", { headers: carolAuth });
    expect((await pairTag(server, carolAuth, "tag-carol")).status).toBe(200);

    const unpairedTag = await scanTag(server, aliceAuth, "bob", "tag-bob");
    expect(unpairedTag.status).toBe(403);
    await expect(readJson(unpairedTag)).resolves.toMatchObject({
      code: "PHYSICAL_ID_MISMATCH",
    });

    const mismatchedTag = await scanTag(server, aliceAuth, "bob", "tag-carol");
    expect(mismatchedTag.status).toBe(403);
    await expect(readJson(mismatchedTag)).resolves.toMatchObject({
      code: "PHYSICAL_ID_MISMATCH",
    });
  });

  it("records only the first scan as first-time collection", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const bobAuth = await authHeaders("bob");

    expect((await pairTag(server, bobAuth, "tag-bob")).status).toBe(200);

    const firstScan = await scanTag(server, aliceAuth, "bob", "tag-bob");
    expect(firstScan.status).toBe(200);
    await expect(readJson(firstScan)).resolves.toMatchObject({
      data: {
        collected_user_id: "bob",
        first_time_collected: true,
      },
    });

    const secondScan = await scanTag(server, aliceAuth, "bob", "tag-bob");
    expect(secondScan.status).toBe(200);
    await expect(readJson(secondScan)).resolves.toMatchObject({
      data: {
        collected_user_id: "bob",
        first_time_collected: false,
      },
    });
  });

  it("normalizes string request fields before storing and comparing IDs", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const bobAuth = await authHeaders("bob");

    const pairResponse = await server.request(
      "/tags/pair",
      await jsonRequest("POST", { physical_id: " tag-bob " }, bobAuth),
    );
    expect(pairResponse.status).toBe(200);

    const scanResponse = await server.request(
      "/collection/scan",
      await jsonRequest("POST", { user_id: " bob ", physical_id: " tag-bob " }, aliceAuth),
    );
    expect(scanResponse.status).toBe(200);
    await expect(readJson(scanResponse)).resolves.toMatchObject({
      data: {
        collected_user_id: "bob",
        first_time_collected: true,
      },
    });

    await expect(
      server.db
        .prepare("SELECT physical_id FROM nfc_tags WHERE user_id = 'bob'")
        .first<{ physical_id: string }>(),
    ).resolves.toEqual({ physical_id: "tag-bob" });
  });
});
