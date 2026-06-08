import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { createTestServer, jsonRequest } from "./helpers";

const CONTRACT_PATHS = [
  "/users/me",
  "/users/me/prize",
  "/users/{user_id}",
  "/tags/pair",
  "/collection/scan",
  "/collections/phishing",
  "/missions/stamp",
  "/scoreboard",
  "/staff/scoreboard_status",
  "/staff/freeze_scoreboard",
  "/staff/resume_scoreboard",
];

const CONTRACT_OPERATIONS = [
  { method: "GET", openapiPath: "/users/me", requestPath: "/users/me" },
  { method: "PATCH", openapiPath: "/users/me", requestPath: "/users/me" },
  { method: "GET", openapiPath: "/users/me/prize", requestPath: "/users/me/prize" },
  { method: "GET", openapiPath: "/users/{user_id}", requestPath: "/users/bob" },
  { method: "POST", openapiPath: "/tags/pair", requestPath: "/tags/pair" },
  { method: "POST", openapiPath: "/collection/scan", requestPath: "/collection/scan" },
  { method: "POST", openapiPath: "/collections/phishing", requestPath: "/collections/phishing" },
  { method: "GET", openapiPath: "/missions/stamp", requestPath: "/missions/stamp" },
  { method: "GET", openapiPath: "/scoreboard", requestPath: "/scoreboard" },
  { method: "GET", openapiPath: "/staff/scoreboard_status", requestPath: "/staff/scoreboard_status" },
  { method: "POST", openapiPath: "/staff/freeze_scoreboard", requestPath: "/staff/freeze_scoreboard" },
  { method: "POST", openapiPath: "/staff/resume_scoreboard", requestPath: "/staff/resume_scoreboard" },
];

describe("OpenAPI contract drift", () => {
  it("documents the expected API paths", () => {
    expect(readOpenApiPaths()).toEqual(CONTRACT_PATHS);
  });

  it("documents scoreboard invalid pagination as a bad request", () => {
    expect(readOpenApiOperationResponses("/scoreboard", "get")).toContain("400");
  });

  it("has mounted routes for every documented operation", async () => {
    const server = await createTestServer();

    for (const operation of CONTRACT_OPERATIONS) {
      const response = await server.request(
        operation.requestPath,
        await requestWithoutCredentials(operation.method),
      );

      expect(response.status, `${operation.method} ${operation.openapiPath}`).toBe(401);
    }
  });
});

function readOpenApiPaths() {
  const testDir = dirname(fileURLToPath(import.meta.url));
  const openApiPath = join(testDir, "../../openapi.yaml");
  const openApi = readFileSync(openApiPath, "utf8");
  const pathMatches = openApi.matchAll(/^  (\/[^:]+):$/gm);

  return [...pathMatches].map((match) => match[1]);
}

function readOpenApiOperationResponses(path: string, method: string) {
  const openApi = readOpenApi();
  const pathIndex = openApi.indexOf(`  ${path}:`);
  expect(pathIndex).toBeGreaterThanOrEqual(0);

  const nextPathIndex = openApi.indexOf("\n  /", pathIndex + 1);
  const pathBlock = openApi.slice(pathIndex, nextPathIndex === -1 ? undefined : nextPathIndex);
  const methodIndex = pathBlock.indexOf(`    ${method}:`);
  expect(methodIndex).toBeGreaterThanOrEqual(0);

  const nextMethodMatch = pathBlock.slice(methodIndex + 1).match(/\n    [a-z]+:/);
  const operationBlock = pathBlock.slice(
    methodIndex,
    nextMethodMatch ? methodIndex + 1 + nextMethodMatch.index! : undefined,
  );
  const responseMatches = operationBlock.matchAll(/^        '(\d{3})':$/gm);

  return [...responseMatches].map((match) => match[1]);
}

function readOpenApi() {
  const testDir = dirname(fileURLToPath(import.meta.url));
  const openApiPath = join(testDir, "../../openapi.yaml");
  return readFileSync(openApiPath, "utf8");
}

async function requestWithoutCredentials(method: string) {
  if (method === "GET") {
    return { method };
  }

  return jsonRequest(method, {});
}
