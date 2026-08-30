-- =====================================================================
-- 02_player_match_map.sql  |  entity resolution: PlayerDB <-> players_external
-- =====================================================================
-- WHY THIS EXISTS
-- players_external has no player_id -- names are its only key, and the two
-- sources write names differently. name_key (build_name_key.sql) normalises
-- accents, punctuation and spacing and resolves 969 of 1039 players.
--
-- The remaining 70 cannot be resolved by any string rule, because the names
-- genuinely differ:
--     MOHAMMAD ABUZRAIQ         =  Sharara          (no shared letters)
--     Alejandro ROMERO GAMARRA  =  Kaku
--     PEDRO MIGUEL              =  Ro-Ro
--     Baba RAHMAN               =  Abdul Rahman Baba (name order)
--     Felix TORRES              =  Felix Torres Caicedo (dropped name part)
--     MOSTAFA ZICO              =  Mostafa Ziko     (transliteration)
--
-- =====================================================================
-- THE METHOD: BLOCK ON NUMBERS, NOT NAMES
-- =====================================================================
-- Stop comparing spellings. Both sources agree EXACTLY on team and on
-- appearance count -- 3288 appearances each, independently recorded -- and
-- closely on minutes. So instead of asking "do these names look alike",
-- ask "who could this possibly be":
--
--   1. anti-join both sides to get the players name_key could not match
--   2. group them by (team, appearances)  <- the blocking key
--   3. a block holding exactly one candidate on each side is a FORCED pair,
--      with no name comparison involved at all
--   4. where a block holds several, rank both sides by minutes, then by
--      shots, and pair rank against rank
--
-- Blocking is why this resolves Sharara. No string algorithm ever pairs
-- ABUZRAIQ with SHARARA, but only one Jordanian played exactly 2 matches
-- and roughly 0 minutes, so the pairing is forced.
--
-- WHY SHOTS IS THE SECOND SORT KEY
-- Two blocks contain players tied on team, appearances AND minutes:
--     Panama      3 apps, 270 min:  Amir MURILLO / Andres ANDRADE
--     Cabo Verde  4 apps, 390 min:  DINEY BORGES / PICO LOPES
-- Minutes cannot separate those, and with an arbitrary sort the algorithm
-- paired Panama BACKWARDS. Shots separates all four cleanly:
--     Amir MURILLO   5 shots -> Michael Amir Murillo   5
--     Andres ANDRADE 0        -> Andres Andrade Cedeno  0
--     DINEY BORGES   4        -> Diney                  4
--     PICO LOPES     2        -> Pico                   2
--
-- Shots is a TIEBREAK, never a blocking key: the two sources agree on it
-- 99.0 percent of the time (959 of 969 rule-matched players), against 100
-- percent for appearances. Good enough to order two candidates already
-- narrowed to the same team and appearance count -- not good enough to
-- group on.
--
-- Team names need aliasing first: the external source writes
-- 'United States' and 'Bosnia-Herz'. That second one contains an EN DASH
-- (U+2013), not a hyphen -- written as CHAR(8211) below, because typing a
-- normal '-' silently matches nothing and drops 23 players.
--
-- =====================================================================
-- THE ONE THING THE QA CHECKS CANNOT SEE
-- =====================================================================
-- A Panama-style swap -- two players of the same team with the same
-- appearance count paired to each other's rows -- passes every check in
-- qa/integrity_checks.sql. Check 6 compares teams (identical), check 7
-- compares appearances (identical). Nothing would catch it.
--
-- So qa/integrity_checks.sql check 12 pins those four pairs explicitly
-- against the human-verified answer. The algorithm derives all 70 rows on
-- its own -- the check exists because this is the one failure mode the
-- other checks are blind to.
--
-- =====================================================================
-- VERIFIED (qa/integrity_checks.sql, checks 5-7 and 12)
-- =====================================================================
--   coverage ................... 1039 / 1039  (100 pct)
--   external rows used twice ...    0
--   team clashes ...............    0
--   appearance mismatches ......    0   <- strongest check: every pair agrees
--   largest minute gap .........    6
--   the four tied pairs ........  pinned by check 12
-- =====================================================================

DROP TABLE IF EXISTS player_match_map;

CREATE TABLE player_match_map (
    player_id         TEXT PRIMARY KEY,
    external_name_key TEXT UNIQUE NOT NULL,   -- UNIQUE is load-bearing: makes
    db_name           TEXT,                   -- it impossible to point two
    external_name     TEXT,                   -- players at one external row
    team              TEXT,
    apps              INTEGER,
    minute_gap        INTEGER
);

INSERT INTO player_match_map
    (player_id, external_name_key, db_name, external_name, team, apps, minute_gap)

WITH match_length AS (
    SELECT match_id, CASE WHEN MAX(m) >= 105 THEN 120 ELSE 90 END AS match_length
    FROM (SELECT match_id, minute AS m                                   FROM player_events
          UNION ALL SELECT match_id, minute                              FROM attempts_at_goal
          UNION ALL SELECT match_id, CAST(subbed_off_minutes AS INTEGER) FROM match_appearances
          UNION ALL SELECT match_id, CAST(subbed_on_minutes  AS INTEGER) FROM match_appearances)
    GROUP BY match_id
),
db AS (
    -- our side: one row per player who appeared, with the blocking attributes
    SELECT p.player_id, p.name_key, p.display_name,
           MIN(ma.team) AS team,
           COUNT(*)     AS apps,
           SUM( MIN( CAST(COALESCE(ma.subbed_off_minutes, ml.match_length) AS INTEGER),
                     COALESCE(CAST(ma.red_card_minutes AS INTEGER), ml.match_length) )
              - MIN( CAST(COALESCE(ma.subbed_on_minutes, 0) AS INTEGER), ml.match_length) ) AS mins,
           COALESCE(SUM(dist.attempts_at_goal), 0) AS shots
    FROM players p
    JOIN match_appearances ma ON ma.player_id = p.player_id AND ma.appeared = 'True'
    JOIN match_length ml      ON ml.match_id  = ma.match_id
    LEFT JOIN player_in_possession_distributions dist ON dist.appearance_id = ma.appearance_id
    GROUP BY p.player_id
),
ext AS (
    -- their side, with the two team-name spellings aliased
    SELECT name_key, player,
           CASE team WHEN 'Bosnia' || CHAR(8211) || 'Herz' THEN 'Bosnia and Herzegovina'
                     WHEN 'United States'                  THEN 'USA'
                     ELSE team END  AS team,
           CAST(games   AS INTEGER) AS apps,
           CAST(minutes AS INTEGER) AS mins,
           CAST(shots   AS INTEGER) AS shots
    FROM players_external
    WHERE minutes IS NOT NULL
),
unmatched_db AS (
    -- step 1: the players name_key could not place
    SELECT d.* FROM db d
    LEFT JOIN ext e ON e.name_key = d.name_key
    WHERE e.name_key IS NULL
),
unmatched_ext AS (
    SELECT e.* FROM ext e
    LEFT JOIN db d ON d.name_key = e.name_key
    WHERE d.name_key IS NULL
),
ranked_db AS (
    -- steps 2-4: block by (team, apps), order within the block by minutes
    -- then shots. name_key is a final tiebreak only so the sort is
    -- deterministic -- it should never actually decide a pairing.
    SELECT *, ROW_NUMBER() OVER (PARTITION BY team, apps
                                 ORDER BY mins DESC, shots DESC, name_key) AS rn
    FROM unmatched_db
),
ranked_ext AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY team, apps
                                 ORDER BY mins DESC, shots DESC, name_key) AS rn
    FROM unmatched_ext
)

-- pair rank against rank inside each block. A block of one is a forced pair.
SELECT d.player_id, e.name_key, d.display_name, e.player,
       d.team, d.apps, ABS(d.mins - e.mins)
FROM ranked_db  d
JOIN ranked_ext e ON e.team = d.team
                 AND e.apps = d.apps
                 AND e.rn   = d.rn;

-- Produces 70 rows, all derived. Run qa/integrity_checks.sql afterwards --
-- check 12 confirms the four tied pairs came out the right way round.

-- =====================================================================
-- HOW TO JOIN THE TWO SOURCES FROM NOW ON
-- =====================================================================
-- COALESCE picks the mapping when one exists, otherwise the rule-based key.
-- One join path covers all 1039 players.
--
--   FROM players d
--   LEFT JOIN player_match_map m ON m.player_id = d.player_id
--   LEFT JOIN players_external e
--          ON e.name_key = COALESCE(m.external_name_key, d.name_key)
--         AND e.minutes IS NOT NULL
--
-- Use LEFT JOIN, never JOIN: if a future data refresh breaks a match, a LEFT
-- JOIN leaves NULLs you can spot, while an inner join silently deletes the
-- player -- which is how entire squads disappear from a dashboard unnoticed.
