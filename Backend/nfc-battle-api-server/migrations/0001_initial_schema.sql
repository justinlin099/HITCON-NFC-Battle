-- Initial D1 schema for the HITCON 2026 NFC Battle backend.
-- Keep this small and evolve it with later API implementation migrations.

CREATE TABLE users (
  user_id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('ATTENDEE', 'STAFF', 'SPONSOR', 'COMMUNITY')),
  emoji_icon TEXT NOT NULL,
  bio TEXT NOT NULL DEFAULT '',
  pixel_avatar_base64 TEXT NOT NULL DEFAULT '',
  profile_version INTEGER NOT NULL DEFAULT 1 CHECK (profile_version >= 0),
  collection_version INTEGER NOT NULL DEFAULT 0 CHECK (collection_version >= 0),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT;

CREATE TABLE nfc_tags (
  physical_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
  paired_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  locked_at TEXT
) STRICT;

CREATE TABLE collections (
  scanner_user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  collected_user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  first_collected_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (scanner_user_id, collected_user_id),
  CHECK (scanner_user_id <> collected_user_id)
) STRICT;

CREATE TRIGGER bump_collection_version_after_insert
AFTER INSERT ON collections
BEGIN
  UPDATE users
  SET
    collection_version = collection_version + 1,
    updated_at = NEW.first_collected_at
  WHERE user_id = NEW.scanner_user_id;
END;

CREATE TABLE phishing_events (
  event_id TEXT PRIMARY KEY,
  victim_user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  attacker_user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  applied_freeze_id TEXT
) STRICT;

CREATE TABLE game_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  state TEXT NOT NULL CHECK (state IN ('OPEN', 'FREEZING', 'FROZEN')),
  freeze_id TEXT,
  freeze_started_at TEXT,
  scoring_cutoff_at TEXT,
  frozen_at TEXT,
  freeze_timeout_seconds INTEGER NOT NULL DEFAULT 30 CHECK (freeze_timeout_seconds > 0),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT;

INSERT INTO game_state (id, state)
VALUES (1, 'OPEN');

CREATE TABLE prize_results (
  freeze_id TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  final_score INTEGER NOT NULL,
  rank INTEGER,
  stamp_prize INTEGER NOT NULL CHECK (stamp_prize IN (0, 1)),
  rank_prize INTEGER NOT NULL CHECK (rank_prize IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (freeze_id, user_id)
) STRICT;

CREATE INDEX idx_nfc_tags_user_id ON nfc_tags(user_id);
CREATE INDEX idx_collections_collected_user_id ON collections(collected_user_id);
CREATE INDEX idx_phishing_events_victim_user_id ON phishing_events(victim_user_id);
CREATE INDEX idx_phishing_events_attacker_user_id ON phishing_events(attacker_user_id);
CREATE INDEX idx_phishing_events_applied_freeze_id ON phishing_events(applied_freeze_id);
CREATE INDEX idx_prize_results_user_id ON prize_results(user_id);
CREATE INDEX idx_prize_results_rank ON prize_results(freeze_id, rank);
