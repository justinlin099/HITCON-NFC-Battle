import { Hono } from "hono";
import { requireAuth } from "./auth";
import { createPrintCard } from "./print-card-store";
import { errorResponse, success } from "./responses";
import type { AppEnv } from "./types";
import { getUserRow } from "./user-store";

const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const MULTIPART_OVERHEAD_BYTES = 64 * 1024;
const RATE_LIMIT_WINDOW_SECONDS = 60;
const REQUEST_TOO_LARGE = Symbol("REQUEST_TOO_LARGE");

const printCards = new Hono<AppEnv>();

printCards.use("*", requireAuth);

printCards.post("/", async (c) => {
  const authUser = c.get("authUser");
  const userRate = await c.env.PRINT_CARD_USER_RATE_LIMITER.limit({ key: authUser.userId });
  if (!userRate.success) {
    return rateLimited(c);
  }

  const globalRate = await c.env.PRINT_CARD_GLOBAL_RATE_LIMITER.limit({ key: "print-cards" });
  if (!globalRate.success) {
    return rateLimited(c);
  }

  const user = await getUserRow(c.env.DB, authUser.userId);
  if (!user) {
    return errorResponse(c, 404, "USER_NOT_FOUND", "User not found.");
  }

  const maxPngBytes = readUploadLimit(c.env.PRINT_CARD_MAX_UPLOAD_BYTES);
  const image = await readPngUpload(c.req.raw, maxPngBytes);
  if (image === "too_large") {
    return errorResponse(c, 413, "PAYLOAD_TOO_LARGE", `PNG image must be at most ${maxPngBytes} bytes.`);
  }
  if (!image) {
    return errorResponse(c, 400, "BAD_REQUEST", "A single PNG image is required.");
  }

  const shortToken = await createPrintCard(
    c.env.DB,
    c.env.PRINT_CARD_IMAGES,
    authUser.userId,
    image,
  );

  return success(c, { short_token: shortToken });
});

export default printCards;

async function readPngUpload(
  request: Request,
  maxPngBytes: number,
): Promise<Uint8Array | "too_large" | null> {
  const contentType = request.headers.get("Content-Type");
  if (!contentType?.toLowerCase().startsWith("multipart/form-data;")) {
    return null;
  }

  const body = await readBodyWithLimit(request, maxPngBytes + MULTIPART_OVERHEAD_BYTES);
  if (body === REQUEST_TOO_LARGE) {
    return "too_large";
  }
  if (!body) {
    return null;
  }

  let form: FormData;
  try {
    form = await new Response(body, { headers: { "Content-Type": contentType } }).formData();
  } catch {
    return null;
  }

  const keys = [...form.keys()];
  if (keys.length !== 1 || keys[0] !== "image" || form.getAll("image").length !== 1) {
    return null;
  }

  const image = form.get("image");
  if (!(image instanceof File) || image.type !== "image/png" || image.size === 0) {
    return null;
  }
  if (image.size > maxPngBytes) {
    return "too_large";
  }

  const bytes = new Uint8Array(await image.arrayBuffer());
  if (!isPng(bytes)) {
    return null;
  }

  return bytes;
}

async function readBodyWithLimit(request: Request, maxBytes: number) {
  const rawContentLength = request.headers.get("Content-Length");
  if (rawContentLength !== null && /^\d+$/.test(rawContentLength)) {
    const contentLength = Number(rawContentLength);
    if (Number.isSafeInteger(contentLength) && contentLength > maxBytes) {
      return REQUEST_TOO_LARGE;
    }
  }

  const reader = request.body?.getReader();
  if (!reader) {
    return null;
  }

  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }

    totalBytes += value.byteLength;
    if (totalBytes > maxBytes) {
      await reader.cancel();
      return REQUEST_TOO_LARGE;
    }
    chunks.push(value);
  }

  const body = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return body;
}

function rateLimited(c: Parameters<typeof errorResponse>[0]) {
  c.header("Retry-After", String(RATE_LIMIT_WINDOW_SECONDS));
  return errorResponse(c, 429, "RATE_LIMITED", "Too many print-card upload requests.");
}

function readUploadLimit(rawLimit: string) {
  if (!/^\d+$/.test(rawLimit)) {
    throw new Error("PRINT_CARD_MAX_UPLOAD_BYTES must be a positive integer.");
  }

  const limit = Number(rawLimit);
  if (!Number.isSafeInteger(limit) || limit < 1) {
    throw new Error("PRINT_CARD_MAX_UPLOAD_BYTES must be a positive integer.");
  }

  return limit;
}

function isPng(bytes: Uint8Array) {
  return bytes.length >= PNG_SIGNATURE.length && PNG_SIGNATURE.every((byte, index) => bytes[index] === byte);
}
