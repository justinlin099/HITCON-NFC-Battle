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
    await expect(
      server.db
        .prepare("SELECT object_key, content_length FROM print_card_objects WHERE short_token = ?1")
        .bind(uploaded.data.short_token)
        .first<{ object_key: string; content_length: number }>(),
    ).resolves.toEqual({
      object_key: expect.stringMatching(/^print-cards\/.+\.png$/),
      content_length: PNG_BYTES.byteLength,
    });
    await expect(
      server.db
        .prepare("SELECT name FROM pragma_table_info('print_card_objects') WHERE name = 'image'")
        .first<{ name: string }>(),
    ).resolves.toBeNull();

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

  it("uses the configured environment upload limit", async () => {
    const server = await createTestServer();
    (server.env as unknown as { PRINT_CARD_MAX_UPLOAD_BYTES: string }).PRINT_CARD_MAX_UPLOAD_BYTES = "8";
    const form = new FormData();
    form.append("image", new Blob([PNG_BYTES], { type: "image/png" }), "card.png");

    const response = await server.request("/print-cards", {
      method: "POST",
      headers: await authHeaders("alice"),
      body: form,
    });

    expect(response.status).toBe(413);
    await expect(readJson(response)).resolves.toMatchObject({ code: "PAYLOAD_TOO_LARGE" });
  });

  it("replaces a user's previous request and deletes its R2 object", async () => {
    const server = await createTestServer();
    const headers = await authHeaders("alice");
    const upload = async () => {
      const form = new FormData();
      form.append("image", new Blob([PNG_BYTES], { type: "image/png" }), "card.png");
      const response = await server.request("/print-cards", { method: "POST", headers, body: form });
      expect(response.status).toBe(200);
      return readJson(response) as Promise<{ data: { short_token: string } }>;
    };

    const first = await upload();
    const firstCard = await server.db
      .prepare("SELECT object_key FROM print_card_objects WHERE short_token = ?1")
      .bind(first.data.short_token)
      .first<{ object_key: string }>();
    expect(firstCard).not.toBeNull();

    const second = await upload();
    expect(second.data.short_token).not.toBe(first.data.short_token);
    await expect(
      server.db
        .prepare("SELECT COUNT(*) AS count FROM print_card_objects WHERE user_id = ?1")
        .bind("alice")
        .first<{ count: number }>(),
    ).resolves.toEqual({ count: 1 });
    await expect(server.env.PRINT_CARD_IMAGES.get(firstCard!.object_key)).resolves.toBeNull();

    const oldToken = await server.request(`/staff/print-cards/${first.data.short_token}`, {
      headers: await authHeaders("staff", "STAFF"),
    });
    expect(oldToken.status).toBe(404);
  });
});
