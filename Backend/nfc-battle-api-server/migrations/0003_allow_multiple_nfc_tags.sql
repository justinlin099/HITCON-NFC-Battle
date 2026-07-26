-- One user may own multiple physical NFC tags. Every UID maps to the same
-- user profile and therefore shares the user's existing nfc_tag_key.
CREATE TABLE nfc_tags_next (
  physical_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  paired_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  locked_at TEXT
) STRICT;

INSERT INTO nfc_tags_next (physical_id, user_id, paired_at, locked_at)
SELECT physical_id, user_id, paired_at, locked_at
FROM nfc_tags;

DROP TABLE nfc_tags;
ALTER TABLE nfc_tags_next RENAME TO nfc_tags;
CREATE INDEX idx_nfc_tags_user_id ON nfc_tags(user_id);
