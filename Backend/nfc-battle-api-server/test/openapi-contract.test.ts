import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { parse } from "yaml";
import { createTestServer, jsonRequest } from "./helpers";

const CONTRACT_PATHS = [
  "/users/me",
  "/users/me/prize",
  "/users/me/bootstrap",
  "/users/batch",
  "/users/{user_id}",
  "/users/{user_id}/collection",
  "/tags/pair",
  "/collection/scan",
  "/collection/phishing",
  "/missions/stamp",
  "/scoreboard",
  "/scoreboard/me",
  "/staff/scoreboard",
  "/staff/scoreboard_status",
  "/staff/pair_user_tag",
  "/staff/unpair_user_tag",
  "/staff/freeze_scoreboard",
  "/staff/resume_scoreboard",
  "/print-cards",
  "/staff/print-cards/{short_token}",
  "/staff/prize-claims",
  "/staff/prize-claims/{user_id}",
  "/staff/nfc-unlock-code",
];

const CONTRACT_OPERATIONS = [
  { method: "GET", openapiPath: "/users/me", requestPath: "/users/me" },
  { method: "PATCH", openapiPath: "/users/me", requestPath: "/users/me" },
  { method: "GET", openapiPath: "/users/me/prize", requestPath: "/users/me/prize" },
  { method: "GET", openapiPath: "/users/me/bootstrap", requestPath: "/users/me/bootstrap" },
  { method: "POST", openapiPath: "/users/batch", requestPath: "/users/batch" },
  { method: "GET", openapiPath: "/users/{user_id}", requestPath: "/users/bob" },
  {
    method: "GET",
    openapiPath: "/users/{user_id}/collection",
    requestPath: "/users/bob/collection",
  },
  { method: "POST", openapiPath: "/tags/pair", requestPath: "/tags/pair" },
  { method: "POST", openapiPath: "/collection/scan", requestPath: "/collection/scan" },
  { method: "POST", openapiPath: "/collection/phishing", requestPath: "/collection/phishing" },
  { method: "GET", openapiPath: "/missions/stamp", requestPath: "/missions/stamp" },
  { method: "GET", openapiPath: "/scoreboard", requestPath: "/scoreboard" },
  { method: "GET", openapiPath: "/scoreboard/me", requestPath: "/scoreboard/me" },
  { method: "GET", openapiPath: "/staff/scoreboard", requestPath: "/staff/scoreboard" },
  { method: "GET", openapiPath: "/staff/scoreboard_status", requestPath: "/staff/scoreboard_status" },
  { method: "POST", openapiPath: "/staff/pair_user_tag", requestPath: "/staff/pair_user_tag" },
  { method: "POST", openapiPath: "/staff/unpair_user_tag", requestPath: "/staff/unpair_user_tag" },
  { method: "POST", openapiPath: "/staff/freeze_scoreboard", requestPath: "/staff/freeze_scoreboard" },
  { method: "POST", openapiPath: "/staff/resume_scoreboard", requestPath: "/staff/resume_scoreboard" },
  { method: "POST", openapiPath: "/print-cards", requestPath: "/print-cards" },
  {
    method: "GET",
    openapiPath: "/staff/print-cards/{short_token}",
    requestPath: "/staff/print-cards/abcdefgh",
  },
  { method: "POST", openapiPath: "/staff/prize-claims", requestPath: "/staff/prize-claims" },
  {
    method: "GET",
    openapiPath: "/staff/prize-claims/{user_id}",
    requestPath: "/staff/prize-claims/alice?type=EXTERNAL",
  },
  { method: "POST", openapiPath: "/staff/nfc-unlock-code", requestPath: "/staff/nfc-unlock-code" },
];

describe("OpenAPI contract drift", () => {
  it("documents the expected API paths", () => {
    expect(readOpenApiPaths()).toEqual(CONTRACT_PATHS);
  });

  it("documents scoreboard invalid pagination as a bad request", () => {
    expect(readOpenApiOperationResponses("/scoreboard", "get")).toContain("400");
  });

  it("documents phishing as unavailable after the event ends", () => {
    expect(readOpenApiOperationResponses("/collection/phishing", "post")).toContain("409");
  });

  it("documents the physical NFC tag ID format", () => {
    const schema = parse(readOpenApi()).components.schemas.PhysicalTagId;

    expect(schema).toMatchObject({
      type: "string",
      minLength: 20,
      maxLength: 20,
      pattern: "^(?:[0-9A-Fa-f]{2}:){6}[0-9A-Fa-f]{2}$",
    });
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
