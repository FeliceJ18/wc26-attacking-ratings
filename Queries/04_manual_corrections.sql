-- =====================================================================
-- 07_manual_corrections.sql  |  manual_playoff_assists
-- =====================================================================
-- THE ONLY DATA IN THIS PROJECT NOT DERIVED FROM A SOURCE TABLE.
-- Everything else can be reproduced by re-running SQL against PlayerDB.db.
-- These six rows were typed in by hand from a published match report, so
-- they are isolated in their own table rather than mixed into the data.
--
-- =====================================================================
-- WHY IT EXISTS
-- =====================================================================
-- 06_player_ratings.sql excludes the third-place playoff (2026-M103-FRA-ENG,
-- France 4-6 England). That match produced 10 goals against a tournament
-- average of 2.96 -- 3.4x the normal rate -- and a playoff generates data by
-- a different process: no trophy, rotated squads, lower intensity.
--
-- The exclusion works cleanly for everything held per match in PlayerDB:
-- goals, take-ons, movement, pressing, line breaks. It does NOT work for
-- assists, because:
--
--   players_external  holds assists as a per-player TOURNAMENT TOTAL with
--                     no match, date or fixture column at all
--   PlayerDB          holds ZERO assist records anywhere
--
-- So without this correction the output rating would mix scopes: goals
-- excluding the playoff, over minutes excluding the playoff, but assists
-- INCLUDING it. Roughly 3 percent of the output data, concentrated entirely
-- in France and England players.
--
-- =====================================================================
-- SOURCE: the seven assists, read off the match report
-- =====================================================================
--    3'     Declan Rice       goal          UNASSISTED
--   18'     Ezri Konsa        header        assist by Declan Rice
--   37'     Bukayo Saka       goal          assist by Marcus Rashford
--   45+1'   Bukayo Saka       goal          assist by Eberechi Eze
--   48'     Kylian Mbappe     goal          assist by Michael Olise
--   54'     Bradley Barcola   goal          assist by Kylian Mbappe
--   66'     Kylian Mbappe     goal          assist by Michael Olise
--   87'     Bukayo Saka       penalty       UNASSISTED
--   90+6'   Ousmane Dembele   goal          assist by Dayot Upamecano
--   90+8'   Jude Bellingham   goal          UNASSISTED
--
-- Ten goals, seven assisted. Cross-check: PlayerDB independently records
-- 10 goals for this match, which matches the report exactly.
--
-- =====================================================================
-- WHY NOT WRITTEN INTO player_events
-- =====================================================================
-- Every event type in player_events is essentially complete across all 104
-- matches:
--     subbed_on    1000 rows / 104 matches
--     subbed_off    998 rows / 104 matches
--     goal          294 rows /  96 matches
--     yellow_card   268 rows /  93 matches
--     own_goal       14 rows /  14 matches
--     red_card       13 rows /  10 matches
--
-- Adding assist rows for ONE fixture would make assist the only event type
-- that is 1-of-104 complete. Anyone running
--     SELECT COUNT(*) FROM player_events WHERE event_type = 'assist'
-- would get 7 and conclude the tournament had seven assists. Partial data
-- inside an otherwise complete column is worse than no data.
--
-- THE REAL FIX, not done here: the match reports carry assists for every
-- goal in all 104 fixtures. Scraping them would give per-match assist data
-- for the whole tournament, make this correction unnecessary, allow assists
-- to be cut by stage or opponent, and reduce players_external to supplying
-- only age and club. That is a scraping job, not a SQL one.
--
-- =====================================================================
-- KEY
-- =====================================================================
-- name_key matches the join key used everywhere else (see build_name_key.sql).
-- Note MICHALOLISE: the German folding rule turns AE into A, so Michael
-- becomes MICHAL. That is correct and consistent on both sides of the join.
--
-- Only 4 of these 6 players clear the 270-minute threshold in
-- 06_player_ratings.sql. Rashford (176 min) and Eze (130 min) fall outside
-- the population, so 5 of the 7 assists are actually subtracted there. The
-- other two are kept so the table stays a complete record of the match.
-- =====================================================================

DROP TABLE IF EXISTS manual_playoff_assists;

CREATE TABLE manual_playoff_assists (
    match_id     TEXT    NOT NULL,
    player_id    TEXT    NOT NULL,
    name_key     TEXT    NOT NULL,
    player_name  TEXT    NOT NULL,
    assists      INTEGER NOT NULL,
    source       TEXT    NOT NULL,
    PRIMARY KEY (match_id, player_id)
);

INSERT INTO manual_playoff_assists VALUES
 ('2026-M103-FRA-ENG','ENG_declan_rice',    'DECLANRICE',    'Declan RICE',    1,
  'published match report for 2026-M103-FRA-ENG (third-place playoff)'),
 ('2026-M103-FRA-ENG','ENG_marcus_rashford','MARCUSRASHFORD','Marcus RASHFORD',1,
  'published match report for 2026-M103-FRA-ENG (third-place playoff)'),
 ('2026-M103-FRA-ENG','ENG_eberechi_eze',   'EBERECHIEZE',   'Eberechi EZE',   1,
  'published match report for 2026-M103-FRA-ENG (third-place playoff)'),
 ('2026-M103-FRA-ENG','FRA_michael_olise',  'MICHALOLISE',   'Michael OLISE',  2,
  'published match report for 2026-M103-FRA-ENG (third-place playoff)'),
 ('2026-M103-FRA-ENG','FRA_kylian_mbappe',  'KYLIANMBAPPE',  'Kylian MBAPPE',  1,
  'published match report for 2026-M103-FRA-ENG (third-place playoff)'),
 ('2026-M103-FRA-ENG','FRA_dayot_upamecano','DAYOTUPAMECANO','Dayot UPAMECANO',1,
  'published match report for 2026-M103-FRA-ENG (third-place playoff)');

-- VERIFY: 6 rows, 7 assists
--   SELECT COUNT(*), SUM(assists) FROM manual_playoff_assists;
--
-- VERIFY the player_ids resolve against PlayerDB:
--   SELECT m.player_name, p.display_name
--   FROM manual_playoff_assists m
--   LEFT JOIN players p ON p.player_id = m.player_id
--   WHERE p.player_id IS NULL;      -- must return 0 rows
--
-- EFFECT on 06_player_ratings.sql:
--   Michael OLISE     7 -> 5 assists    rank  1 -> 6
--   Kylian MBAPPE     4 -> 3            rank  1 (unchanged)
--   Declan RICE       2 -> 1            rank 117
--   Dayot UPAMECANO   1 -> 0            rank 279
