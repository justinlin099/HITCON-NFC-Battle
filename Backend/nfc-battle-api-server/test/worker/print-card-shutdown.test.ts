import { env } from "cloudflare:workers";
import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

const TEST_JWT_SECRET = "test-secret";

describe("retired print-card routes", () => {
  it("rejects requests before accessing the disabled R2 binding", async () => {
    const attendeeToken = await signJwt("alice", "ATTENDEE");
    const staffToken = await signJwt("staff", "STAFF");

    const upload = await SELF.fetch("https://localhost/print-cards", {
      method: "POST",
      headers: { Authorization: `Bearer ${attendeeToken}` },
    });
    expect(upload.status).toBe(409);
    await expect(upload.json()).resolves.toMatchObject({ code: "EVENT_ENDED" });

    const download = await SELF.fetch("https://localhost/staff/print-cards/abcdefgh", {
      headers: { Authorization: `Bearer ${staffToken}` },
    });
    expect(download.status).toBe(409);
    await expect(download.json()).resolves.toMatchObject({ code: "EVENT_ENDED" });
  });
});

async function signJwt(subject: string, role: "ATTENDEE" | "STAFF") {
  const header = encodeJson({ alg: "HS256", typ: "JWT" });
  const payload = encodeJson({
    sub: subject,
    role,
    iss: env.JWT_ISSUER,
    aud: env.JWT_AUDIENCE,
    exp: Math.floor(Date.now() / 1000) + 300,
  });
  const signingInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(TEST_JWT_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signingInput)),
  );
  return `${signingInput}.${encodeBytes(signature)}`;
}

function encodeJson(value: unknown) {
  return encodeBytes(new TextEncoder().encode(JSON.stringify(value)));
}

function encodeBytes(value: Uint8Array) {
  let binary = "";
  for (const byte of value) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
