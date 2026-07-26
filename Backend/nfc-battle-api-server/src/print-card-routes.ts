import { Hono } from "hono";
import { requireAuth } from "./auth";
import { createPrintCard } from "./print-card-store";
import { errorResponse, success } from "./responses";
import type { AppEnv } from "./types";
import { lazyInitializeUser } from "./user-store";

const MAX_PNG_BYTES = 5 * 1024 * 1024;
const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

const printCards = new Hono<AppEnv>();

printCards.use("*", requireAuth);

printCards.post("/", async (c) => {
  const image = await readPngUpload(c.req.raw);
  if (image === "too_large") {
    return errorResponse(c, 413, "PAYLOAD_TOO_LARGE", "PNG image must be at most 5 MiB.");
  }
  if (!image) {
    return errorResponse(c, 400, "BAD_REQUEST", "A single PNG image is required.");
  }

  const authUser = c.get("authUser");
  await lazyInitializeUser(c.env.DB, authUser.userId, authUser.role);
  const shortToken = await createPrintCard(c.env.DB, authUser.userId, image);

  return success(c, { short_token: shortToken });
});

export default printCards;

async function readPngUpload(request: Request): Promise<Uint8Array | "too_large" | null> {
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
  if (image.size > MAX_PNG_BYTES) {
    return "too_large";
  }

  const bytes = new Uint8Array(await image.arrayBuffer());
  if (!isPng(bytes)) {
    return null;
  }

  return bytes;
}

function isPng(bytes: Uint8Array) {
  return bytes.length >= PNG_SIGNATURE.length && PNG_SIGNATURE.every((byte, index) => bytes[index] === byte);
}
