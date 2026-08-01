-- Current request paths do not query these reverse foreign-key columns.
-- Primary-key and uniqueness constraints remain unchanged.
DROP INDEX idx_collections_collected_user_id;
DROP INDEX idx_phishing_events_attacker_user_id;
DROP INDEX idx_prize_results_user_id;
DROP INDEX idx_print_card_objects_user_id;
DROP INDEX idx_prize_claims_user_id;
