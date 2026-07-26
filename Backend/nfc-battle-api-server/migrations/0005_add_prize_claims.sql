-- A user can collect at most once for each frozen scoreboard snapshot.
CREATE TABLE prize_claims (
  freeze_id TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  claimed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  claimed_by_user_id TEXT NOT NULL,
  PRIMARY KEY (freeze_id, user_id)
) STRICT;

CREATE INDEX idx_prize_claims_user_id ON prize_claims(user_id);
