-- =====================================================================
-- qa/integrity_checks.sql  |  data integrity assertions
-- =====================================================================
-- EVERY QUERY IN THIS FILE MUST RETURN ZERO ROWS.
-- A row returned is a failure, and the comment above each check says what
-- that failure would mean.
--
-- These are not summary statistics. Each one is a statement that must be
-- true of correct data, checkable without any external source. Four of the
-- five bugs in 00_data_cleaning.sql were found by checks like these, not by
-- reading totals -- because every one of those bugs produced totals that
-- looked entirely reasonable.
--
-- Run this after any change to the data or the pipeline.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. SUBSTITUTIONS BALANCE
-- ---------------------------------------------------------------------
-- A substitution is one player off, one player on. So within a team-match,
-- the count of subbed-on players must equal the count of subbed-off.
--
-- FOUND: two missing subbed_off records, both Jefferson Lerma, in
-- M071-COL-POR and M096-SUI-COL. Confirmed against published match reports
-- (60' and 82', both Richard Rios replacing him). He was being credited
-- with 70 minutes he did not play.
-- ---------------------------------------------------------------------
SELECT match_id, team,
       SUM(CASE WHEN subbed_on_minutes  IS NOT NULL THEN 1 ELSE 0 END) AS ons,
       SUM(CASE WHEN subbed_off_minutes IS NOT NULL THEN 1 ELSE 0 END) AS offs
FROM match_appearances
GROUP BY match_id, team
HAVING ons <> offs;


-- ---------------------------------------------------------------------
-- 2. GOALS RECONCILE TO THE SCORELINES
-- ---------------------------------------------------------------------
-- Player goals plus own goals must equal the sum of every scoreline. The
-- scorelines are independent of the player-level tables, so this catches
-- a goal credited to the wrong player or the wrong category.
--
-- FOUND: the second source credited Switzerland's own goal (Muheim,
-- M008-QAT-SUI, 95') to Qatar's Boualem Khoukhi, who took zero shots in
-- that match. Both sources totalled 308 -- one just had the goal in the
-- wrong column. PlayerDB was correct.
-- ---------------------------------------------------------------------
SELECT (SELECT SUM(goals) FROM player_in_possession_distributions)        AS player_goals,
       (SELECT COUNT(*) FROM player_events WHERE event_type = 'own_goal') AS own_goals,
       (SELECT SUM(home_score + away_score) FROM matches)                 AS scorelines
WHERE  (SELECT SUM(goals) FROM player_in_possession_distributions)
     + (SELECT COUNT(*) FROM player_events WHERE event_type = 'own_goal')
    <> (SELECT SUM(home_score + away_score) FROM matches);


-- ---------------------------------------------------------------------
-- 3. NO IMPOSSIBLE MINUTES
-- ---------------------------------------------------------------------
-- Nobody plays negative minutes, and nobody plays longer than the match.
--
-- FOUND: 109 negative values, which is how the extra-time problem surfaced
-- originally -- substitutes entering at minute 122 in matches assumed to
-- end at 90. Also the second-yellow dismissals, since a player sent off
-- was otherwise credited to the final whistle.
-- ---------------------------------------------------------------------
WITH match_length AS (
    SELECT match_id, CASE WHEN MAX(m) >= 105 THEN 120 ELSE 90 END AS match_length
    FROM (SELECT match_id, minute AS m                                   FROM player_events
          UNION ALL SELECT match_id, minute                              FROM attempts_at_goal
          UNION ALL SELECT match_id, CAST(subbed_off_minutes AS INTEGER) FROM match_appearances
          UNION ALL SELECT match_id, CAST(subbed_on_minutes  AS INTEGER) FROM match_appearances)
    GROUP BY match_id
),
mins AS (
    SELECT ma.player_name, ma.match_id, ml.match_length,
           MIN( CAST(COALESCE(ma.subbed_off_minutes, ml.match_length) AS INTEGER),
                ml.match_length,
                COALESCE( CAST(ma.red_card_minutes AS INTEGER),
                          CASE WHEN INSTR(ma.yellow_card_minutes, ' ') > 0
                               THEN CAST(SUBSTR(ma.yellow_card_minutes,
                                         INSTR(ma.yellow_card_minutes, ' ') + 1) AS INTEGER) END,
                          ml.match_length ) )
         - MIN( CAST(COALESCE(ma.subbed_on_minutes, 0) AS INTEGER), ml.match_length ) AS minutes
    FROM match_appearances ma
    JOIN match_length ml ON ml.match_id = ma.match_id
    WHERE ma.appeared = 'True'
)
SELECT * FROM mins WHERE minutes < 0 OR minutes > match_length;


-- ---------------------------------------------------------------------
-- 4. name_key IS UNIQUE WITHIN THE JOINED POPULATION
-- ---------------------------------------------------------------------
-- The match key must identify one player. If two share it, both join to
-- the same external row and one gets another player's stats.
--
-- Scoped to players who appeared, because that is the population every
-- query joins on. There IS one collision across the full players table:
--     ARG_emiliano_martinez   Emiliano MARTINEZ   Argentina   8 apps
--     URU_emiliano_martinez   Emiliano MARTINEZ   Uruguay     0 apps
-- Two genuinely different players with identical names. Harmless today
-- because the Uruguayan never played and is filtered out everywhere --
-- but it would become a real bug if the appeared filter were ever removed.
-- ---------------------------------------------------------------------
SELECT d.name_key, COUNT(*) AS players_sharing_it
FROM players d
JOIN (SELECT player_id FROM match_appearances
      WHERE appeared = 'True' GROUP BY player_id) t ON t.player_id = d.player_id
WHERE d.name_key IS NOT NULL
GROUP BY d.name_key
HAVING COUNT(*) > 1;


-- ---------------------------------------------------------------------
-- 5. NO EXTERNAL ROW IS CLAIMED BY TWO PLAYERS
-- ---------------------------------------------------------------------
-- The reverse of check 4. If two PlayerDB players resolve to the same
-- external row, one of them is wearing someone else's assists.
-- ---------------------------------------------------------------------
SELECT e.name_key, COUNT(*) AS claimed_by
FROM players d
LEFT JOIN player_match_map m ON m.player_id = d.player_id
JOIN players_external e      ON e.name_key  = COALESCE(m.external_name_key, d.name_key)
                            AND e.minutes IS NOT NULL
JOIN (SELECT player_id FROM match_appearances
      WHERE appeared = 'True' GROUP BY player_id) t ON t.player_id = d.player_id
GROUP BY e.name_key
HAVING COUNT(*) > 1;


-- ---------------------------------------------------------------------
-- 6. MATCHED PAIRS AGREE ON TEAM
-- ---------------------------------------------------------------------
-- Two sources independently recording the same player must agree on which
-- country he played for. This is the guard against a false name match.
--
-- The two CASE branches are known spelling differences, not errors.
-- NOTE: 'Bosnia-Herz' in the external source uses an EN DASH (U+2013), not
-- a hyphen. Typing it with a normal '-' silently matches nothing and the
-- check reports 23 false failures -- written as CHAR(8211) to avoid that.
-- ---------------------------------------------------------------------
SELECT d.display_name, t.team AS playerdb_team, e.team AS external_team
FROM players d
LEFT JOIN player_match_map m ON m.player_id = d.player_id
JOIN players_external e      ON e.name_key  = COALESCE(m.external_name_key, d.name_key)
                            AND e.minutes IS NOT NULL
JOIN (SELECT player_id, MIN(team) AS team FROM match_appearances
      WHERE appeared = 'True' GROUP BY player_id) t ON t.player_id = d.player_id
WHERE t.team <> CASE e.team
                    WHEN 'Bosnia' || CHAR(8211) || 'Herz' THEN 'Bosnia and Herzegovina'
                    WHEN 'United States'                  THEN 'USA'
                    ELSE e.team
                END;


-- ---------------------------------------------------------------------
-- 7. MATCHED PAIRS AGREE ON APPEARANCE COUNT
-- ---------------------------------------------------------------------
-- The strongest check of the entity resolution. Both sources total 3,288
-- appearances independently, and appearances are an integer rather than an
-- estimate -- so a mismatched pair almost certainly means two different
-- people were joined together.
--
-- This is also what made the 70 manual matches trustworthy: they were
-- resolved BY team and appearance count rather than by name, and every one
-- of the 1,039 pairs agrees here.
-- ---------------------------------------------------------------------
SELECT d.display_name,
       COUNT(*)                  AS playerdb_appearances,
       CAST(e.games AS INTEGER)  AS external_appearances
FROM players d
LEFT JOIN player_match_map m ON m.player_id = d.player_id
JOIN players_external e      ON e.name_key  = COALESCE(m.external_name_key, d.name_key)
                            AND e.minutes IS NOT NULL
JOIN match_appearances ma    ON ma.player_id = d.player_id AND ma.appeared = 'True'
GROUP BY d.player_id
HAVING COUNT(*) <> CAST(e.games AS INTEGER);


-- ---------------------------------------------------------------------
-- 8. MANUAL CORRECTIONS STILL POINT AT REAL PLAYERS
-- ---------------------------------------------------------------------
-- manual_playoff_assists is hand-entered (see 04_manual_corrections.sql).
-- Hand-entered keys are exactly the ones that rot when IDs change, so this
-- verifies every one still resolves.
-- ---------------------------------------------------------------------
SELECT m.player_name, m.player_id
FROM manual_playoff_assists m
LEFT JOIN players p ON p.player_id = m.player_id
WHERE p.player_id IS NULL;


-- ---------------------------------------------------------------------
-- 9. NO LIGATURE CHARACTERS REMAIN
-- ---------------------------------------------------------------------
-- The source PDFs encoded "fi" as a single character (U+FB01). It broke
-- every equality and LIKE filter it touched -- searching for knockout
-- matches returned 1 row of 8, silently. Cleaned in 00_data_cleaning.sql --
-- this confirms it stays clean, including after any re-import.
-- ---------------------------------------------------------------------
SELECT 'players.display_name' AS location, display_name AS value
FROM players           WHERE display_name LIKE '%ﬁ%'
UNION ALL
SELECT 'matches.group', "group"
FROM matches           WHERE "group" LIKE '%ﬁ%'
UNION ALL
SELECT 'match_appearances.player_name', player_name
FROM match_appearances WHERE player_name LIKE '%ﬁ%';


-- ---------------------------------------------------------------------
-- 10. THE EXTRA-TIME THRESHOLD IS NOT A GUESS
-- ---------------------------------------------------------------------
-- Extra time is not labelled anywhere in the data, so match length is
-- inferred: a match whose latest recorded event passes minute 105 went to
-- extra time. 105 would be arbitrary except that NO match has a last event
-- between 103 and 112 -- regulation tops out at 102, extra time starts at
-- 113. Any threshold inside that empty band gives the identical 9 matches,
-- so the result does not depend on the number chosen.
--
-- This check asserts the band is still empty. If a future data refresh puts
-- a match in it, the threshold has become a judgement call and needs
-- revisiting rather than silently changing the answer.
--
-- See qa/match_length_inspection.sql to view the full distribution.
-- ---------------------------------------------------------------------
SELECT match_id, MAX(m) AS last_min
FROM (SELECT match_id, minute AS m                                   FROM player_events
      UNION ALL SELECT match_id, minute                              FROM attempts_at_goal
      UNION ALL SELECT match_id, CAST(subbed_off_minutes AS INTEGER) FROM match_appearances
      UNION ALL SELECT match_id, CAST(subbed_on_minutes  AS INTEGER) FROM match_appearances)
GROUP BY match_id
HAVING last_min BETWEEN 103 AND 112;


-- ---------------------------------------------------------------------
-- 11. NO GROUP-STAGE MATCH IS FLAGGED AS EXTRA TIME
-- ---------------------------------------------------------------------
-- Group matches end level -- only knockout ties go to extra time. The
-- threshold in check 10 was derived purely from event minutes with no
-- knowledge of the tournament structure, so this is a genuinely
-- independent confirmation that it lands in the right place.
--
-- All 9 extra-time matches are M074 or later -- the knockout stage.
-- ---------------------------------------------------------------------
SELECT m.match_id, m."group"
FROM matches m
WHERE m."group" LIKE 'Group%'
  AND m.match_id IN (
      SELECT match_id FROM (
          SELECT match_id, MAX(x) AS last_min
          FROM (SELECT match_id, minute AS x                                   FROM player_events
                UNION ALL SELECT match_id, minute                              FROM attempts_at_goal
                UNION ALL SELECT match_id, CAST(subbed_off_minutes AS INTEGER) FROM match_appearances
                UNION ALL SELECT match_id, CAST(subbed_on_minutes  AS INTEGER) FROM match_appearances)
          GROUP BY match_id
          HAVING last_min >= 105));


-- ---------------------------------------------------------------------
-- 12. THE FOUR TIED PAIRS CAME OUT THE RIGHT WAY ROUND
-- ---------------------------------------------------------------------
-- 02_player_match_map.sql derives all 70 mappings by blocking on
-- (team, appearances) and ordering within a block by minutes, then shots.
--
-- Two blocks contain players tied on team, appearances AND minutes:
--     Panama      3 apps, 270 min:  Amir MURILLO / Andres ANDRADE
--     Cabo Verde  4 apps, 390 min:  DINEY BORGES / PICO LOPES
-- Shots separates all four, and the algorithm gets them right. But before
-- shots was added as a tiebreak the sort was arbitrary and it paired
-- PANAMA BACKWARDS -- Andrade to Murillo and vice versa.
--
-- WHY THIS CHECK EXISTS: no other check in this file can see that failure.
-- A swap between two players of the same team with the same appearance
-- count passes check 6 (teams identical) and check 7 (appearances
-- identical). It is the one mispairing the suite is blind to, so the
-- human-verified answer is pinned here explicitly.
--
-- Shots agree between the sources only 99.0 percent of the time, so if a
-- future refresh moved one of these four, the algorithm could silently flip
-- a pair. This check would catch it.
-- ---------------------------------------------------------------------
WITH expected(player_id, external_name_key) AS (
    VALUES ('PAN_amir_murillo',   'MICHALAMIRMURILLO'),   -- MICHAEL folds to MICHAL (AE -> A)
           ('PAN_andres_andrade', 'ANDRESANDRADECEDENO'),
           ('CPV_diney_borges',   'DINEY'),
           ('CPV_pico_lopes',     'PICO')
)
SELECT x.player_id,
       x.external_name_key AS should_be,
       m.external_name_key AS actually_is
FROM expected x
LEFT JOIN player_match_map m ON m.player_id = x.player_id
WHERE m.external_name_key IS NULL
   OR m.external_name_key <> x.external_name_key;


-- ---------------------------------------------------------------------
-- 13. EVERY SQUAD HOLDS EXACTLY 26 PLAYERS
-- ---------------------------------------------------------------------
-- The 2026 World Cup is 48 teams naming 26 players each, so the players
-- table must hold exactly 26 rows per team_id. This is the only check in
-- this file that tests the data against the COMPETITION'S RULES rather
-- than against the other source or against itself -- it needs no external
-- file and could have been written before any data was loaded.
--
-- WOULD HAVE FOUND BOTH ID BUGS ON DAY ONE. Against the raw import
-- (PlayerDB_original.db, 1277 players) it returns exactly four rows, and
-- they name the two defects and the precise squads involved:
--     GHA  52   <- FIX 2: 26 Uzbek players duplicated under Ghana's code
--     FRA  27   <- FIX 3: FRA_dembele   split from FRA_ousmane_dembele
--     MAR  27   <- FIX 3: MAR_ounahi    split from MAR_azzedine_ounahi
--     NED  27   <- FIX 3: NED_crysencio split from NED_crysencio_summerville
--
-- 1277 raw  -  26 duplicates  -  3 split identities  =  1248  =  48 x 26.
-- Both sources independently land on 1248, and neither was tuned to it.
--
-- Nothing else in the suite tests total population. Checks 4-7 compare the
-- two sources, so a player duplicated identically in BOTH would pass them
-- all; this check would not.
-- ---------------------------------------------------------------------
SELECT team_id, COUNT(*) AS squad_size
FROM players
GROUP BY team_id
HAVING COUNT(*) <> 26;


-- ---------------------------------------------------------------------
-- 14. THE TOURNAMENT HAS 48 TEAMS
-- ---------------------------------------------------------------------
-- The companion to check 13, which counts within each squad but cannot
-- see a squad that is absent entirely -- GROUP BY only returns groups that
-- exist. Together the two pin the population at exactly 48 x 26 = 1248.
--
-- This one passed even on the raw import: the Ghana bug duplicated players
-- INTO an existing team_id rather than inventing a new one, so the team
-- count stayed correct while the player count was wrong by 29. That is
-- precisely why both checks are needed and not just one.
-- ---------------------------------------------------------------------
SELECT COUNT(DISTINCT team_id) AS teams
FROM players
HAVING COUNT(DISTINCT team_id) <> 48;
