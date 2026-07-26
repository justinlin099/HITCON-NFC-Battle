-- Print-card PNGs are stored in R2. D1 stores only the opaque barcode token
-- and object metadata used by the staff-protected download endpoint.
CREATE TABLE print_card_objects (
  short_token TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  object_key TEXT NOT NULL UNIQUE,
  content_length INTEGER NOT NULL CHECK (content_length > 0),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT;

CREATE INDEX idx_print_card_objects_user_id ON print_card_objects(user_id);
