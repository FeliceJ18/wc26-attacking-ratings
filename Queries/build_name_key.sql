-- =====================================================================
-- build_name_key.sql  |  canonical match key joining the two player sources
-- =====================================================================
-- Rebuilds name_key from scratch on both tables. Safe to re-run.
--
-- WHY THIS IS SPLIT INTO MANY SMALL UPDATES:
-- 49 nested REPLACE() calls in one expression overflows SQLite parser
-- stack. Each UPDATE below applies at most 8 replacements to the column
-- built by the previous one. Same result, and far easier to read.
--
-- RULES, in order. Both sides get identical treatment:
--   1. strip 41 accented characters
--        NOTE: O-slash, sharp-s and the Turkish dotless-i do NOT decompose
--        under standard Unicode accent-stripping; they are mapped by hand
--   2. UPPER()  -- must come AFTER step 1: SQLite UPPER is ASCII-only
--   3. remove apostrophes, hyphens, periods, commas, spaces
--        ONEILL   <- ONEILL / O Neill        ALHAMADI <- ALHAMADI / Al Hamadi
--   4. fold German UE/OE/AE -> U/O/A         RUDIGER  <- RUEDIGER / Rudiger
--   (a literal apostrophe inside a SQL string is written as two apostrophes)
--
-- EACH RULE MEASURED AND VERIFIED BEFORE BEING KEPT:
--   accents only ......... 917 matched
--   + punctuation/spaces . 966
--   + German folding ..... 969  of 1039  (93.3 pct)
--   key collisions: 0 both sides.   team mismatches: 0 across all pairs.
--
-- The ~70 still unmatched need judgment, not rules: nicknames, dropped
-- name parts, transliteration variants, name-order swaps.
-- =====================================================================

-- ---------- create the column ----------
-- RUN THESE TWO ONCE, on a database that does not yet have name_key.
-- SQLite has no ADD COLUMN IF NOT EXISTS, so re-running them on a database
-- that already has the column raises "duplicate column name: name_key".
-- That error is harmless -- skip these two lines and run the UPDATEs below,
-- which rebuild the values from scratch and are safe to repeat.
--
-- players_external must exist first: it is the second Kaggle dataset
-- (playersdata.csv) imported via DB Browser and renamed. See the README.

ALTER TABLE players          ADD COLUMN name_key TEXT;
ALTER TABLE players_external ADD COLUMN name_key TEXT;

-- ---------- PlayerDB side (already plain ASCII, so no accent step) ----------
UPDATE players SET name_key = UPPER(display_name);
UPDATE players SET name_key = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(name_key,'''',''),'-',''),'.',''),' ',''),',','');
UPDATE players SET name_key = REPLACE(REPLACE(REPLACE(name_key,'UE','U'),'OE','O'),'AE','A');

-- ---------- external side ----------
UPDATE players_external SET name_key = player;
UPDATE players_external SET name_key = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(name_key,'ß','ss'),'Á','A'),'Ç','C'),'É','E'),'Ö','O'),'Ø','O'),'á','a'),'â','a');
UPDATE players_external SET name_key = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(name_key,'ã','a'),'å','a'),'ç','c'),'è','e'),'é','e'),'ë','e'),'í','i'),'ï','i');
UPDATE players_external SET name_key = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(name_key,'ñ','n'),'ó','o'),'ö','o'),'ø','o'),'ú','u'),'ü','u'),'ý','y'),'Ć','C');
UPDATE players_external SET name_key = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(name_key,'ć','c'),'Č','C'),'č','c'),'ě','e'),'ğ','g'),'İ','I'),'ı','i'),'Ō','O');
UPDATE players_external SET name_key = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(name_key,'ō','o'),'ř','r'),'ş','s'),'Š','S'),'š','s'),'ū','u'),'ů','u'),'ž','z');
UPDATE players_external SET name_key = REPLACE(name_key,'ʻ','');
UPDATE players_external SET name_key = UPPER(name_key);
UPDATE players_external SET name_key = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(name_key,'''',''),'-',''),'.',''),' ',''),',','');
UPDATE players_external SET name_key = REPLACE(REPLACE(REPLACE(name_key,'UE','U'),'OE','O'),'AE','A');


-- =====================================================================
-- TEAM NAME ALIASES -- needed for any team-level comparison
-- =====================================================================
-- Two teams are spelled differently between the sources:
--
--   PlayerDB 'Bosnia and Herzegovina'   external 'Bosnia–Herz'
--   PlayerDB 'USA'                      external 'United States'
--
-- WARNING: 'Bosnia–Herz' contains an EN DASH (U+2013), not a hyphen.
-- Typing it with a normal '-' silently matches nothing -- the same class
-- of bug as the fi-ligature in 00_data_cleaning.sql. In SQL, write it as
-- 'Bosnia' || CHAR(8211) || 'Herz' so the character is unambiguous.
--
-- Verification query -- must return 0 rows:
--
--   SELECT d.display_name, t.team, e.player, e.team
--   FROM players d
--   JOIN players_external e ON d.name_key = e.name_key AND e.minutes IS NOT NULL
--   JOIN (SELECT player_id, MIN(team) team FROM match_appearances
--         WHERE appeared='True' GROUP BY player_id) t ON t.player_id = d.player_id
--   WHERE t.team <> CASE e.team
--                     WHEN 'Bosnia' || CHAR(8211) || 'Herz' THEN 'Bosnia and Herzegovina'
--                     WHEN 'United States' THEN 'USA'
--                     ELSE e.team END;
--
-- Currently 0. Confirms no false matches: every pair that agrees on name
-- also agrees on team.
