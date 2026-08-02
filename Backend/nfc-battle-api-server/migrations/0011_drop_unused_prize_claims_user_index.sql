-- Current prize claim lookups and scoreboard joins use the composite primary
-- key (type, freeze_id, user_id). There is no user-deletion request path that
-- needs a separate user_id index for cascading deletes.
DROP INDEX idx_prize_claims_user_id;
