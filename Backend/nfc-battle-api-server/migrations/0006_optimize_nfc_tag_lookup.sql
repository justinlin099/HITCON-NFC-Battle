DROP INDEX idx_nfc_tags_user_id;

CREATE INDEX idx_nfc_tags_user_pairing_order
ON nfc_tags(user_id, paired_at, physical_id);
