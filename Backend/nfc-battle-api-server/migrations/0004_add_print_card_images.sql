-- PNGs are stored alongside their opaque barcode token. They are only served
-- through a staff-protected endpoint.
CREATE TABLE print_card_images (
  short_token TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  image BLOB NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT;

CREATE INDEX idx_print_card_images_user_id ON print_card_images(user_id);
