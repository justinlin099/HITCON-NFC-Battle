import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { DatabaseSync, type SQLInputValue } from "node:sqlite";
import { fileURLToPath } from "node:url";
import app from "../src/index";
import type { AppBindings, UserRole } from "../src/types";

const JWT_SECRET = "test-secret";
const JWT_ISSUER = "hitcon-2026";
const JWT_AUDIENCE = "nfc-battle-api-server";

class TestD1PreparedStatement {
  private readonly values: SQLInputValue[] = [];

  constructor(
    private readonly db: DatabaseSync,
    private readonly query: string,
  ) {}

  bind(...values: unknown[]) {
    this.values.splice(0, this.values.length, ...(values as SQLInputValue[]));
    return this;
  }

  async run() {
    const result = this.db.prepare(this.query).run(...this.values);
    return {
      success: true,
      meta: {
        changes: result.changes,
        last_row_id: Number(result.lastInsertRowid),
      },
    };
  }

  async first<T = Record<string, unknown>>() {
    return (this.db.prepare(this.query).get(...this.values) ?? null) as T | null;
  }

  async all<T = Record<string, unknown>>() {
    const results = this.db.prepare(this.query).all(...this.values) as T[];
    return {
      success: true,
      results,
      meta: {},
    };
  }
}

class TestD1Database {
  constructor(private readonly db: DatabaseSync) {}

  prepare(query: string) {
    return new TestD1PreparedStatement(this.db, query);
  }

  async exec(query: string) {
    this.db.exec(query);
    return {
      count: 1,
      duration: 0,
    };
  }
}

export interface TestServer {
  env: AppBindings;
  db: D1Database;
  request(path: string, init?: RequestInit): Promise<Response>;
}

export async function createTestServer(): Promise<TestServer> {
  const sqlite = new DatabaseSync(":memory:");
  const db = new TestD1Database(sqlite) as unknown as D1Database;
  const testDir = dirname(fileURLToPath(import.meta.url));
  const migrationPath = join(testDir, "../migrations/0001_initial_schema.sql");
  await db.exec(readFileSync(migrationPath, "utf8"));

  const env = {
    DB: db,
    ASSETS: {} as Fetcher,
    JWT_SECRET,
    STAFF_DANGER_TOKEN: "test-staff-token",
    JWT_ISSUER,
    JWT_AUDIENCE,
  } satisfies AppBindings;

  return {
    env,
    db,
    request(path, init) {
      return Promise.resolve(app.request(`https://localhost${path}`, init, env));
    },
  };
}

export async function authHeaders(userId: string, role: UserRole = "ATTENDEE") {
  return {
    Authorization: `Bearer ${await signJwt(userId, role)}`,
  };
}

export function staffHeaders() {
  return {
    STAFF_DANGER_TOKEN: "test-staff-token",
  };
}

export async function jsonRequest(
  method: string,
  body: unknown,
  headers: Record<string, string> = {},
): Promise<RequestInit> {
  return {
    method,
    headers: {
      "Content-Type": "application/json",
      ...headers,
    },
    body: JSON.stringify(body),
  };
}

export async function readJson(response: Response) {
  return response.json() as Promise<unknown>;
}

export async function signJwt(
  userId: string,
  role: UserRole = "ATTENDEE",
  overrides: Record<string, unknown> = {},
) {
  const header = { alg: "HS256", typ: "JWT" };
  const payload = {
    sub: userId,
    exp: Math.floor(Date.now() / 1000) + 3600,
    iss: JWT_ISSUER,
    aud: JWT_AUDIENCE,
    role,
    ...overrides,
  };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = await crypto.subtle.sign(
    { name: "HMAC", hash: "SHA-256" },
    await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(JWT_SECRET),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    ),
    new TextEncoder().encode(signingInput),
  );

  return `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

function base64UrlEncode(value: string | Uint8Array) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  const binary = String.fromCharCode(...bytes);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
