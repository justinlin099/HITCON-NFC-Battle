import { describe, expect, it } from "vitest";
import { authenticateJwt } from "../src/auth";
import { isFreezingStale } from "../src/freeze";
import { calculateScore } from "../src/scoring";
import type { AppBindings } from "../src/types";
import { signJwt } from "./helpers";

const env = {
  JWT_SECRET: "test-secret",
  JWT_ISSUER: "hitcon-2026",
  JWT_AUDIENCE: "nfc-battle-api-server",
} as AppBindings;

describe("JWT authentication", () => {
  it("accepts a valid HS256 token with required claims", async () => {
    const token = await signJwt("kktix_hash_abc123", "STAFF");

    await expect(authenticateJwt(`Bearer ${token}`, env)).resolves.toMatchObject({
      userId: "kktix_hash_abc123",
      role: "STAFF",
      issuer: "hitcon-2026",
      audience: "nfc-battle-api-server",
    });
  });

  it("rejects expired tokens", async () => {
    const token = await signJwt("kktix_hash_abc123", "ATTENDEE", { exp: 1 });

    await expect(authenticateJwt(`Bearer ${token}`, env)).rejects.toThrow();
  });

  it("rejects wrong audience tokens", async () => {
    const token = await signJwt("kktix_hash_abc123", "ATTENDEE", { aud: "other-api" });

    await expect(authenticateJwt(`Bearer ${token}`, env)).rejects.toThrow();
  });
});

describe("scoring helpers", () => {
  it("uses the current provisional score formula", () => {
    expect(calculateScore(0)).toBe(0);
    expect(calculateScore(7)).toBe(70);
  });

  it("detects stale FREEZING state after timeout", () => {
    expect(isFreezingStale("FREEZING", "2026-04-12T15:00:00.000Z", 300, new Date("2026-04-12T15:06:00.000Z"))).toBe(true);
    expect(isFreezingStale("FREEZING", "2026-04-12T15:00:00.000Z", 300, new Date("2026-04-12T15:04:00.000Z"))).toBe(false);
    expect(isFreezingStale("OPEN", "2026-04-12T15:00:00.000Z", 300, new Date("2026-04-12T15:06:00.000Z"))).toBe(false);
  });
});
