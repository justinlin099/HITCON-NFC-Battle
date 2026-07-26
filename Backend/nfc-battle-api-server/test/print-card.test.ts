import { describe, expect, it } from "vitest";
import { authHeaders, createTestServer, readJson } from "./helpers";

const PNG_BYTES = new Uint8Array([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00,
]);

describe("print cards", () => {
  it("issues a short token for a PNG and only lets staff download it", async () => {
    const server = await createTestServer();
    const attendeeHeaders = await authHeaders("alice");
    const form = new FormData();
    form.append("image", new Blob([PNG_BYTES], { type: "image/png" }), "card.png");

    const upload = await server.request("/print-cards", {
      method: "POST",
      headers: attendeeHeaders,
      body: form,
    });
    expect(upload.status).toBe(200);
    const uploaded = await readJson(upload) as { data: { short_token: string } };
    expect(uploaded.data.short_token).toMatch(/^[A-Za-z0-9_-]{11}$/);

    const denied = await server.request(`/staff/print-cards/${uploaded.data.short_token}`, {
      headers: attendeeHeaders,
    });
    expect(denied.status).toBe(403);

    const download = await server.request(`/staff/print-cards/${uploaded.data.short_token}`, {
      headers: await authHeaders("staff", "STAFF"),
    });
    expect(download.status).toBe(200);
    expect(download.headers.get("Content-Type")).toBe("image/png");
    expect(new Uint8Array(await download.arrayBuffer())).toEqual(PNG_BYTES);
  });

  it("rejects non-PNG print-card uploads", async () => {
    const server = await createTestServer();
    const form = new FormData();
    form.append("image", new Blob([new Uint8Array([1, 2, 3])], { type: "image/png" }), "bad.png");

    const response = await server.request("/print-cards", {
      method: "POST",
      headers: await authHeaders("alice"),
      body: form,
    });

    expect(response.status).toBe(400);
    await expect(readJson(response)).resolves.toMatchObject({ code: "BAD_REQUEST" });
  });
});
