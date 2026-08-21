import { describe, expect, it } from "vitest";
import {
  authHeaders,
  createTestServer,
  jsonRequest,
  readJson,
  staffHeaders,
} from "./helpers";

describe("attendee rate limits", () => {
  it("limits each authenticated user independently for each route", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");

    for (let request = 0; request < 20; request += 1) {
      const response = await server.request("/users/me", { headers: aliceAuth });
      expect(response.status).toBe(200);
    }

    const limited = await server.request("/users/me", { headers: aliceAuth });
    expect(limited.status).toBe(429);
    expect(limited.headers.get("Retry-After")).toBe("60");
    await expect(readJson(limited)).resolves.toMatchObject({ code: "RATE_LIMITED" });

    const separateRoute = await server.request("/users/me/prize", { headers: aliceAuth });
    expect(separateRoute.status).toBe(409);

    const bobAuth = await authHeaders("bob");
    const separateUser = await server.request("/users/me", { headers: bobAuth });
    expect(separateUser.status).toBe(200);
  });

  it("counts invalid authenticated requests toward the endpoint limit", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    await server.request("/users/me", { headers: aliceAuth });

    for (let request = 0; request < 5; request += 1) {
      const response = await server.request(
        "/tags/pair",
        await jsonRequest("POST", { physical_id: "invalid" }, aliceAuth),
      );
      expect(response.status).toBe(400);
    }

    const limited = await server.request(
      "/tags/pair",
      await jsonRequest("POST", { physical_id: "invalid" }, aliceAuth),
    );
    expect(limited.status).toBe(429);
  });

  it("does not apply attendee limits to staff routes", async () => {
    const server = await createTestServer();
    const staffAuth = await authHeaders("staff", "STAFF");
    await server.request("/users/me", { headers: staffAuth });

    for (let request = 0; request < 3; request += 1) {
      const response = await server.request("/users/me/bootstrap", { headers: staffAuth });
      expect(response.status).toBe(200);
    }
    const limitedAttendeeRoute = await server.request("/users/me/bootstrap", {
      headers: staffAuth,
    });
    expect(limitedAttendeeRoute.status).toBe(429);

    const staffRoute = await server.request("/staff/scoreboard_status", {
      headers: { ...staffAuth, ...staffHeaders() },
    });
    expect(staffRoute.status).toBe(200);
  });
});
