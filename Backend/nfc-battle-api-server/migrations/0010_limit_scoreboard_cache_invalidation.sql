-- Only external prize claims affect the scoreboard response. Stamp and ranking
-- claims must not invalidate cached scoreboard pages.
DROP TRIGGER bump_prize_claims_version_after_insert;

CREATE TRIGGER bump_prize_claims_version_after_insert
AFTER INSERT ON prize_claims
WHEN NEW.type = 'EXTERNAL'
BEGIN
  UPDATE prize_claims_state
  SET version = version + 1
  WHERE id = 1;
END;
