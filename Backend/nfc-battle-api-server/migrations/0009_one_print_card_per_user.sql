-- Keep one current print card per user. Existing duplicate metadata keeps the
-- newest card; future replacements delete the old R2 object in application code.
DELETE FROM print_card_objects
WHERE short_token IN (
  SELECT short_token
  FROM (
    SELECT
      short_token,
      ROW_NUMBER() OVER (
        PARTITION BY user_id
        ORDER BY created_at DESC, short_token DESC
      ) AS row_number
    FROM print_card_objects
  )
  WHERE row_number > 1
);

CREATE UNIQUE INDEX idx_print_card_objects_user_id
ON print_card_objects(user_id);
