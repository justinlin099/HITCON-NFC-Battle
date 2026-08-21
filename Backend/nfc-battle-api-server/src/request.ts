import type { Context } from "hono";
import type { AppEnv } from "./types";

const PHYSICAL_TAG_ID_PATTERN = /^(?:[0-9A-F]{2}:){6}[0-9A-F]{2}$/;
export const JSON_BODY_TOO_LARGE = Symbol("JSON_BODY_TOO_LARGE");

export async function readJson(c: Context<AppEnv>) {
  try {
    return (await c.req.json()) as unknown;
  } catch {
    return null;
  }
}

export async function readJsonWithLimit(c: Context<AppEnv>, maxBytes: number) {
  const contentLength = Number(c.req.header("Content-Length"));
  if (Number.isFinite(contentLength) && contentLength > maxBytes) {
    return JSON_BODY_TOO_LARGE;
  }

  const reader = c.req.raw.body?.getReader();
  if (!reader) {
    return null;
  }

  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }

      totalBytes += value.byteLength;
      if (totalBytes > maxBytes) {
        await reader.cancel();
        return JSON_BODY_TOO_LARGE;
      }
      chunks.push(value);
    }

    const body = new Uint8Array(totalBytes);
    let offset = 0;
    for (const chunk of chunks) {
      body.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return JSON.parse(new TextDecoder().decode(body)) as unknown;
  } catch {
    return null;
  }
}

export function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function hasOnlyKeys(value: Record<string, unknown>, allowedKeys: Set<string>) {
  return Object.keys(value).every((key) => allowedKeys.has(key));
}

export function requiredString(value: Record<string, unknown>, key: string) {
  const fieldValue = value[key];
  if (typeof fieldValue !== "string") {
    return null;
  }

  const trimmed = fieldValue.trim();
  return trimmed === "" ? null : trimmed;
}

export function requiredPhysicalTagId(value: Record<string, unknown>, key: string) {
  const fieldValue = requiredString(value, key);
  if (!fieldValue) {
    return null;
  }

  const normalized = fieldValue.toUpperCase();
  return PHYSICAL_TAG_ID_PATTERN.test(normalized) ? normalized : null;
}
