-- Preserve a compact, queryable summary of the event's phishing activity.
-- Timestamps and freeze markers apply to a whole victim/attacker aggregate;
-- distinctions between individual events are intentionally discarded.
CREATE TABLE phishing_events_condensed (
  victim_id TEXT NOT NULL,
  attacker_id TEXT NOT NULL,
  count INTEGER NOT NULL,
  last_created_at TEXT NOT NULL,
  applied_freeze_id TEXT,
  PRIMARY KEY (victim_id, attacker_id),
  FOREIGN KEY (victim_id) REFERENCES users(user_id),
  FOREIGN KEY (attacker_id) REFERENCES users(user_id)
) STRICT;

INSERT INTO phishing_events_condensed (
  victim_id,
  attacker_id,
  count,
  last_created_at,
  applied_freeze_id
)
SELECT
  victim_user_id AS victim_id,
  attacker_user_id AS attacker_id,
  COUNT(*) AS count,
  MAX(created_at) AS last_created_at,
  MAX(applied_freeze_id) AS applied_freeze_id
FROM phishing_events
GROUP BY victim_user_id, attacker_user_id
ORDER BY last_created_at;

DROP TABLE phishing_events;
