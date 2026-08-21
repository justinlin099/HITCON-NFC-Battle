import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { DatabaseSync, type SQLInputValue } from "node:sqlite";
import { fileURLToPath } from "node:url";
import app from "../src/index";
import {
  ScoreboardCoordinatorService,
  getScoreboardCoordinator,
  type ScoreboardCoordinatorScheduler,
  type ScoreboardCoordinatorStorage,
  type StoredCoordinatorState,
} from "../src/scoreboard-coordinator-service";
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

class TestR2Bucket {
  private readonly objects = new Map<string, { body: Uint8Array; contentType?: string }>();

  async put(key: string, value: Uint8Array, options?: R2PutOptions) {
    this.objects.set(key, {
      body: new Uint8Array(value),
      contentType: options?.httpMetadata instanceof Headers
        ? options.httpMetadata.get("Content-Type") ?? undefined
        : options?.httpMetadata?.contentType,
    });
    return {} as R2Object;
  }

  async get(key: string) {
    const object = this.objects.get(key);
    if (!object) {
      return null;
    }

    const body = new Uint8Array(object.body);
    return {
      body: new ReadableStream<Uint8Array>({
        start(controller) {
          controller.enqueue(body);
          controller.close();
        },
      }),
      httpMetadata: { contentType: object.contentType },
    } as R2ObjectBody;
  }

  async delete(key: string) {
    this.objects.delete(key);
  }
}

class TestRateLimit {
  private readonly counts = new Map<string, number>();

  constructor(private readonly limitValue: number) {}

  async limit({ key }: { key: string }) {
    const count = (this.counts.get(key) ?? 0) + 1;
    this.counts.set(key, count);
    return { success: count <= this.limitValue };
  }
}

class TestScoreboardStorage implements ScoreboardCoordinatorStorage {
  private state: StoredCoordinatorState = {
    control: undefined,
    snapshot: undefined,
    pending_snapshot: undefined,
  };

  async readState() {
    return { ...this.state };
  }

  async writeState(update: Partial<StoredCoordinatorState>) {
    this.state = { ...this.state, ...update };
  }
}

class TestScoreboardScheduler implements ScoreboardCoordinatorScheduler {
  scheduledDelayMs: number | null = null;

  async schedule(delayMs: number) {
    this.scheduledDelayMs = delayMs;
  }

  async stop() {
    this.scheduledDelayMs = null;
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
  const migrationsDir = join(testDir, "../migrations");
  for (const migrationFile of readdirSync(migrationsDir).sort()) {
    await db.exec(readFileSync(join(migrationsDir, migrationFile), "utf8"));
  }

  const env = {
    DB: db,
    ASSETS: {} as Fetcher,
    PRINT_CARD_IMAGES: new TestR2Bucket() as unknown as R2Bucket,
    AUTH_HEALTH_RATE_LIMITER: new TestRateLimit(10) as unknown as RateLimit,
    MY_PROFILE_READ_RATE_LIMITER: new TestRateLimit(20) as unknown as RateLimit,
    MY_PROFILE_UPDATE_RATE_LIMITER: new TestRateLimit(10) as unknown as RateLimit,
    MY_PRIZE_READ_RATE_LIMITER: new TestRateLimit(20) as unknown as RateLimit,
    MY_BOOTSTRAP_RATE_LIMITER: new TestRateLimit(3) as unknown as RateLimit,
    USER_BATCH_READ_RATE_LIMITER: new TestRateLimit(20) as unknown as RateLimit,
    USER_PROFILE_READ_RATE_LIMITER: new TestRateLimit(30) as unknown as RateLimit,
    USER_COLLECTION_READ_RATE_LIMITER: new TestRateLimit(5) as unknown as RateLimit,
    TAG_PAIR_RATE_LIMITER: new TestRateLimit(5) as unknown as RateLimit,
    COLLECTION_SCAN_RATE_LIMITER: new TestRateLimit(30) as unknown as RateLimit,
    PHISHING_RECORD_RATE_LIMITER: new TestRateLimit(3) as unknown as RateLimit,
    STAMP_MISSION_READ_RATE_LIMITER: new TestRateLimit(60) as unknown as RateLimit,
    SCOREBOARD_READ_RATE_LIMITER: new TestRateLimit(20) as unknown as RateLimit,
    MY_SCOREBOARD_READ_RATE_LIMITER: new TestRateLimit(20) as unknown as RateLimit,
    PRINT_CARD_USER_RATE_LIMITER: new TestRateLimit(5) as unknown as RateLimit,
    PRINT_CARD_GLOBAL_RATE_LIMITER: new TestRateLimit(300) as unknown as RateLimit,
    PRINT_CARD_MAX_UPLOAD_BYTES: "4194304",
    SCOREBOARD_REFRESH_SECONDS: "10",
    JWT_SECRET,
    STAFF_DANGER_TOKEN: "test-staff-token",
    JWT_ISSUER,
    JWT_AUDIENCE,
  } as AppBindings;

  const scoreboardCoordinator = new ScoreboardCoordinatorService(
    () => env,
    new TestScoreboardStorage(),
    new TestScoreboardScheduler(),
  );
  env.SCOREBOARD_COORDINATOR = {
    getByName() {
      return scoreboardCoordinator;
    },
  } as unknown as AppBindings["SCOREBOARD_COORDINATOR"];

  return {
    env,
    db,
    async request(path, init) {
      const backgroundTasks: Promise<unknown>[] = [];
      const executionCtx = {
        waitUntil(promise: Promise<unknown>) {
          backgroundTasks.push(promise);
        },
        passThroughOnException() {},
      } as ExecutionContext;
      const response = await app.request(`https://localhost${path}`, init, env, executionCtx);
      await Promise.all(backgroundTasks);
      return response;
    },
  };
}

export async function refreshScoreboard(server: TestServer) {
  await getScoreboardCoordinator(server.env).refreshNow();
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

export async function initializeUser(
  server: TestServer,
  userId: string,
  role: UserRole = "ATTENDEE",
) {
  const headers = await authHeaders(userId, role);
  const response = await server.request("/users/me", { headers });
  return { headers, response };
}

export async function pairTag(
  server: TestServer,
  headers: Record<string, string>,
  physicalId: string,
) {
  return server.request(
    "/tags/pair",
    await jsonRequest("POST", { physical_id: physicalId }, headers),
  );
}

export async function scanTag(
  server: TestServer,
  headers: Record<string, string>,
  userId: string,
  physicalId: string,
) {
  return server.request(
    "/collection/scan",
    await jsonRequest("POST", { user_id: userId, physical_id: physicalId }, headers),
  );
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
