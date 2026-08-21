-- Shorten legacy profile text without splitting a UTF-8 character.
UPDATE users
SET
  display_name = (
  WITH RECURSIVE prefixes(character_count) AS (
    VALUES(0)
    UNION ALL
    SELECT character_count + 1
    FROM prefixes
    WHERE character_count < length(users.display_name)
  )
  SELECT substr(users.display_name, 1, MAX(character_count))
  FROM prefixes
  WHERE length(CAST(substr(users.display_name, 1, character_count) AS BLOB)) <= 100
  ),
  profile_version = profile_version + 1
WHERE length(CAST(display_name AS BLOB)) > 100;

UPDATE users
SET
  emoji_icon = (
  WITH RECURSIVE prefixes(character_count) AS (
    VALUES(0)
    UNION ALL
    SELECT character_count + 1
    FROM prefixes
    WHERE character_count < length(users.emoji_icon)
  )
  SELECT substr(users.emoji_icon, 1, MAX(character_count))
  FROM prefixes
  WHERE length(CAST(substr(users.emoji_icon, 1, character_count) AS BLOB)) <= 64
  ),
  profile_version = profile_version + 1
WHERE length(CAST(emoji_icon AS BLOB)) > 64;

UPDATE users
SET
  bio = (
  WITH RECURSIVE prefixes(character_count) AS (
    VALUES(0)
    UNION ALL
    SELECT character_count + 1
    FROM prefixes
    WHERE character_count < length(users.bio)
  )
  SELECT substr(users.bio, 1, MAX(character_count))
  FROM prefixes
  WHERE length(CAST(substr(users.bio, 1, character_count) AS BLOB)) <= 4096
  ),
  profile_version = profile_version + 1
WHERE length(CAST(bio AS BLOB)) > 4096;
