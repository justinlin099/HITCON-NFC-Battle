import type { Context } from "hono";
import type { AppEnv } from "./types";

export async function readJson(c: Context<AppEnv>) {
  try {
    return (await c.req.json()) as unknown;
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
  return trimmed === "" ? null : fieldValue;
}
