import { describe, expect, it } from "vitest";
import { authHeaders, createTestServer, readJson } from "./helpers";

describe("retired print-card feature", () => {
  it("rejects attendee upload and staff download routes after the event", async () => {
    const server = await createTestServer();
    const attendeeAuth = await authHeaders("alice");
    const staffAuth = await authHeaders("staff", "STAFF");

    const upload = await server.request("/print-cards", {
      method: "POST",
      headers: attendeeAuth,
    });
    expect(upload.status).toBe(409);
    await expect(readJson(upload)).resolves.toMatchObject({ code: "EVENT_ENDED" });

    const download = await server.request("/staff/print-cards/abcdefgh", {
      headers: staffAuth,
    });
    expect(download.status).toBe(409);
    await expect(readJson(download)).resolves.toMatchObject({ code: "EVENT_ENDED" });
  });
});
