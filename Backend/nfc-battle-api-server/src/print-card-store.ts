import { nowIso } from "./ids";

export interface PrintCardImageRow {
  user_id: string;
  image: ArrayBuffer | Uint8Array;
}

const SHORT_TOKEN_BYTES = 8;
const MAX_SHORT_TOKEN_ATTEMPTS = 5;

export async function createPrintCard(
  db: D1Database,
  userId: string,
  image: Uint8Array,
) {
  for (let attempt = 0; attempt < MAX_SHORT_TOKEN_ATTEMPTS; attempt += 1) {
    const shortToken = newShortToken();
    const result = await db
      .prepare(
        `
        INSERT OR IGNORE INTO print_card_images (short_token, user_id, image, created_at)
        VALUES (?1, ?2, ?3, ?4)
        `,
      )
      .bind(shortToken, userId, image, nowIso())
      .run();

    if (result.meta.changes > 0) {
      return shortToken;
    }
  }

  throw new Error("Could not allocate a unique print-card token.");
}

export async function getPrintCard(db: D1Database, shortToken: string) {
  return db
    .prepare(
      `
      SELECT user_id, image
      FROM print_card_images
      WHERE short_token = ?1
      `,
    )
    .bind(shortToken)
    .first<PrintCardImageRow>();
}

function newShortToken() {
  const bytes = new Uint8Array(SHORT_TOKEN_BYTES);
  crypto.getRandomValues(bytes);
  const binary = String.fromCharCode(...bytes);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
