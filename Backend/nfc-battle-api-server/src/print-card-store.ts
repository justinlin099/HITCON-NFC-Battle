import { nowIso } from "./ids";

export interface PrintCardObjectRow {
  short_token: string;
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
    const previousCard = await getPrintCardForUser(db, userId);
    const shortToken = newShortToken();
    const objectKey = `print-cards/${crypto.randomUUID()}.png`;
    await bucket.put(objectKey, image, {
      httpMetadata: { contentType: "image/png" },
    });

    let result;
    try {
      result = previousCard
        ? await db
          .prepare(
            `
            UPDATE OR IGNORE print_card_objects
            SET
              short_token = ?1,
              object_key = ?3,
              content_length = ?4,
              created_at = ?5
            WHERE user_id = ?2 AND short_token = ?6
            `,
          )
          .bind(shortToken, userId, objectKey, image.byteLength, nowIso(), previousCard.short_token)
          .run()
        : await db
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

    } catch (error) {
      await bucket.delete(objectKey);
      throw error;
    }

    if (result.meta.changes > 0) {
      if (previousCard) {
        await bucket.delete(previousCard.object_key);
      }
      return shortToken;
    }

    await bucket.delete(objectKey);
  }

  throw new Error("Could not allocate a unique print-card token.");
}

export async function getPrintCard(db: D1Database, shortToken: string) {
  return db
    .prepare(
      `
      SELECT short_token, user_id, object_key
      FROM print_card_objects
      WHERE short_token = ?1
      `,
    )
    .bind(shortToken)
    .first<PrintCardObjectRow>();
}

async function getPrintCardForUser(db: D1Database, userId: string) {
  return db
    .prepare(
      `
      SELECT short_token, user_id, object_key
      FROM print_card_objects
      WHERE user_id = ?1
      `,
    )
    .bind(userId)
    .first<PrintCardObjectRow>();
}

function newShortToken() {
  const bytes = new Uint8Array(SHORT_TOKEN_BYTES);
  crypto.getRandomValues(bytes);
  const binary = String.fromCharCode(...bytes);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
