import { nowIso } from "./ids";

export interface PrintCardObjectRow {
  user_id: string;
  object_key: string;
}

const SHORT_TOKEN_BYTES = 8;
const MAX_SHORT_TOKEN_ATTEMPTS = 5;

export async function createPrintCard(
  db: D1Database,
  bucket: R2Bucket,
  userId: string,
  image: Uint8Array,
) {
  for (let attempt = 0; attempt < MAX_SHORT_TOKEN_ATTEMPTS; attempt += 1) {
    const shortToken = newShortToken();
    const objectKey = `print-cards/${crypto.randomUUID()}.png`;
    await bucket.put(objectKey, image, {
      httpMetadata: { contentType: "image/png" },
    });

    try {
      const result = await db
        .prepare(
          `
          INSERT OR IGNORE INTO print_card_objects (
            short_token,
            user_id,
            object_key,
            content_length,
            created_at
          )
          VALUES (?1, ?2, ?3, ?4, ?5)
          `,
        )
        .bind(shortToken, userId, objectKey, image.byteLength, nowIso())
        .run();

      if (result.meta.changes > 0) {
        return shortToken;
      }
    } catch (error) {
      await bucket.delete(objectKey);
      throw error;
    }

    await bucket.delete(objectKey);
  }

  throw new Error("Could not allocate a unique print-card token.");
}

export async function getPrintCard(db: D1Database, shortToken: string) {
  return db
    .prepare(
      `
      SELECT user_id, object_key
      FROM print_card_objects
      WHERE short_token = ?1
      `,
    )
    .bind(shortToken)
    .first<PrintCardObjectRow>();
}

function newShortToken() {
  const bytes = new Uint8Array(SHORT_TOKEN_BYTES);
  crypto.getRandomValues(bytes);
  const binary = String.fromCharCode(...bytes);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
