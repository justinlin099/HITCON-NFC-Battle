ALTER TABLE users ADD COLUMN nfc_tag_key TEXT;

UPDATE users
SET nfc_tag_key = lower(hex(randomblob(6)))
WHERE nfc_tag_key IS NULL;
