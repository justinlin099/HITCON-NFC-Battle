-- Store external, stamp, and ranking redemptions in the existing claim log.
-- External and stamp claims use an empty freeze_id so each is unique per user.
-- Ranking claims remain unique per user and frozen scoreboard snapshot.
CREATE TABLE prize_claims_next (
  type TEXT NOT NULL CHECK (type IN ('EXTERNAL', 'STAMP', 'RANKING')),
  freeze_id TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  claimed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  claimed_by_user_id TEXT NOT NULL,
  PRIMARY KEY (type, freeze_id, user_id),
  CHECK (
    (type IN ('EXTERNAL', 'STAMP') AND freeze_id = '')
    OR (type = 'RANKING' AND length(freeze_id) > 0)
  )
) STRICT;

INSERT OR IGNORE INTO prize_claims_next (type, freeze_id, user_id, claimed_at, claimed_by_user_id)
SELECT 'STAMP', '', prize_claims.user_id, prize_claims.claimed_at, prize_claims.claimed_by_user_id
FROM prize_claims
INNER JOIN prize_results
  ON prize_results.freeze_id = prize_claims.freeze_id
  AND prize_results.user_id = prize_claims.user_id
WHERE prize_results.stamp_prize = 1;

INSERT INTO prize_claims_next (type, freeze_id, user_id, claimed_at, claimed_by_user_id)
SELECT 'RANKING', prize_claims.freeze_id, prize_claims.user_id, prize_claims.claimed_at, prize_claims.claimed_by_user_id
FROM prize_claims
INNER JOIN prize_results
  ON prize_results.freeze_id = prize_claims.freeze_id
  AND prize_results.user_id = prize_claims.user_id
WHERE prize_results.rank_prize = 1;

DROP TABLE prize_claims;
ALTER TABLE prize_claims_next RENAME TO prize_claims;
CREATE INDEX idx_prize_claims_user_id ON prize_claims(user_id);

-- Scoreboard cache keys include this version so an external redemption appears
-- immediately instead of waiting for a cached scoreboard page to expire.
CREATE TABLE prize_claims_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  version INTEGER NOT NULL DEFAULT 0 CHECK (version >= 0)
) STRICT;

INSERT INTO prize_claims_state (id, version)
VALUES (1, 0);

CREATE TRIGGER bump_prize_claims_version_after_insert
AFTER INSERT ON prize_claims
BEGIN
  UPDATE prize_claims_state
  SET version = version + 1
  WHERE id = 1;
END;
