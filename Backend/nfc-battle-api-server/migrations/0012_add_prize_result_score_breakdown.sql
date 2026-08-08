-- Preserve the score inputs so users can inspect the exact frozen calculation.
ALTER TABLE prize_results
ADD COLUMN num_of_collection INTEGER NOT NULL DEFAULT 0 CHECK (num_of_collection >= 0);

ALTER TABLE prize_results
ADD COLUMN num_of_phishing INTEGER NOT NULL DEFAULT 0 CHECK (num_of_phishing >= 0);

ALTER TABLE prize_results
ADD COLUMN score_per_collection INTEGER NOT NULL DEFAULT 10 CHECK (score_per_collection >= 0);

ALTER TABLE prize_results
ADD COLUMN phishing_penalty INTEGER NOT NULL DEFAULT 10 CHECK (phishing_penalty >= 0);

-- A valid deployment keeps at most the current frozen snapshot. Backfill it
-- from the same cutoff and applied phishing markers used by the freeze flow.
UPDATE prize_results
SET
  num_of_collection = (
    SELECT COUNT(*)
    FROM collections
    WHERE collections.scanner_user_id = prize_results.user_id
      AND collections.first_collected_at <= (
        SELECT scoring_cutoff_at
        FROM game_state
        WHERE id = 1
          AND state = 'FROZEN'
          AND freeze_id = prize_results.freeze_id
      )
  ),
  num_of_phishing = (
    SELECT COUNT(*)
    FROM phishing_events
    WHERE phishing_events.victim_user_id = prize_results.user_id
      AND phishing_events.applied_freeze_id = prize_results.freeze_id
  )
WHERE prize_results.freeze_id = (
  SELECT freeze_id
  FROM game_state
  WHERE id = 1 AND state = 'FROZEN'
);
