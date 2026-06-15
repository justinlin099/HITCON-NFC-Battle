import { describe, expect, it } from "vitest";
import { authHeaders, createTestServer, jsonRequest, readJson } from "./helpers";

describe("phishing event edge cases", () => {
  it("rejects unauthenticated phishing requests", async () => {
    const server = await createTestServer();

    const response = await server.request(
      "/collection/phishing",
      await jsonRequest("POST", { victim: "alice", attacker: "bob" }),
    );

    expect(response.status).toBe(401);
    await expect(readJson(response)).resolves.toMatchObject({
      code: "UNAUTHORIZED",
    });
  });

  it("rejects invalid phishing request bodies", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");

    for (const body of [
      {},
      { victim: "alice" },
      { attacker: "bob" },
      { victim: "", attacker: "bob" },
      { victim: "alice", attacker: "" },
      { victim: "alice", attacker: "bob", extra: "nope" },
    ]) {
      const response = await server.request(
        "/collection/phishing",
        await jsonRequest("POST", body, aliceAuth),
      );

      expect(response.status).toBe(400);
      await expect(readJson(response)).resolves.toMatchObject({
        code: "BAD_REQUEST",
      });
    }
  });

  it("rejects missing authenticated victim rows", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const bobAuth = await authHeaders("bob");
    await server.request("/users/me", { headers: bobAuth });

    const response = await server.request(
      "/collection/phishing",
      await jsonRequest("POST", { victim: "alice", attacker: "bob" }, aliceAuth),
    );

    expect(response.status).toBe(404);
    await expect(readJson(response)).resolves.toMatchObject({
      code: "USER_NOT_FOUND",
    });
  });

  it("rejects victim mismatch, self phishing, and unknown attackers", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    await server.request("/users/me", { headers: aliceAuth });

    const victimMismatch = await server.request(
      "/collection/phishing",
      await jsonRequest("POST", { victim: "bob", attacker: "alice" }, aliceAuth),
    );
    expect(victimMismatch.status).toBe(400);

    const selfPhishing = await server.request(
      "/collection/phishing",
      await jsonRequest("POST", { victim: "alice", attacker: "alice" }, aliceAuth),
    );
    expect(selfPhishing.status).toBe(400);

    const unknownAttacker = await server.request(
      "/collection/phishing",
      await jsonRequest("POST", { victim: "alice", attacker: "bob" }, aliceAuth),
    );
    expect(unknownAttacker.status).toBe(400);
  });

  it("records phishing when victim is caller and attacker exists", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const bobAuth = await authHeaders("bob");
    await server.request("/users/me", { headers: aliceAuth });
    await server.request("/users/me", { headers: bobAuth });

    const response = await server.request(
      "/collection/phishing",
      await jsonRequest("POST", { victim: "alice", attacker: "bob" }, aliceAuth),
    );

    expect(response.status).toBe(200);
    await expect(readJson(response)).resolves.toMatchObject({
      message: "Phishing event recorded.",
    });
  });
});
