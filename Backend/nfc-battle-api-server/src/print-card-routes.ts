import { Hono } from "hono";
import { requireAuth } from "./auth";
import { createPrintCard } from "./print-card-store";
import { errorResponse, success } from "./responses";
import type { AppEnv } from "./types";
import { lazyInitializeUser } from "./user-store";

const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

const printCards = new Hono<AppEnv>();

printCards.use("*", requireAuth);

printCards.post("/", async (c) => {
  const maxPngBytes = readUploadLimit(c.env.PRINT_CARD_MAX_UPLOAD_BYTES);
  const image = await readPngUpload(c.req.raw, maxPngBytes);
  if (image === "too_large") {
    return errorResponse(c, 413, "PAYLOAD_TOO_LARGE", `PNG image must be at most ${maxPngBytes} bytes.`);
  }
  if (!image) {
    return errorResponse(c, 400, "BAD_REQUEST", "A single PNG image is required.");
  }

  const authUser = c.get("authUser");
  await lazyInitializeUser(c.env.DB, authUser.userId, authUser.role);
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
  let form: FormData;
  try {
    form = await request.formData();
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
