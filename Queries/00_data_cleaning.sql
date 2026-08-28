-- =====================================================================
-- 00_data_cleaning.sql   |   run once, before anything else
-- =====================================================================
-- PROBLEM
-- The source data was extracted from PDFs. In print, "fi" is drawn as a
-- single joined glyph (a ligature), and the extraction preserved it as ONE
-- character (U+FB01) instead of the two letters f + i.
--
-- Effect: any text containing lowercase "fi" is one character short and will
-- NOT match a normally-typed string. It fails silently -- no error, just
-- zero rows.
--
--   SELECT COUNT(*) FROM matches WHERE "group" LIKE '%final%';
--     before cleaning: 1 row     <- lost 7 of 8 knockout matches
--     after  cleaning: 8 rows
--
-- SCOPE
-- 422 rows across 13 columns in 13 tables. Stage names in matches."group",
-- and player display names everywhere (Rafik Belghali, Alfie Jones,
-- Soufiane Rahimi).
--
-- player_id was NOT affected -- it is stored lowercase and spelled out
-- ("ALG_rafik_belghali"), so all joins on player_id were always correct.
-- Only human-readable text was corrupted.
--
-- U+FB01 was the only ligature present; no other non-ASCII damage found.
--
-- SAFETY
-- No WHERE clause is needed: REPLACE returns text unchanged when the search
-- string is absent, so untouched rows stay identical. Re-running is harmless
-- (after the first run there is nothing left to find).
--
-- Original file preserved as PlayerDB_original.db before running this.
-- =====================================================================

UPDATE matches                            SET "group"      = REPLACE("group",      'ﬁ', 'fi');
UPDATE players                            SET display_name = REPLACE(display_name, 'ﬁ', 'fi');

UPDATE match_appearances                  SET player_name  = REPLACE(player_name,  'ﬁ', 'fi');
UPDATE attempts_at_goal                   SET player_name  = REPLACE(player_name,  'ﬁ', 'fi');
UPDATE player_events                      SET player_name  = REPLACE(player_name,  'ﬁ', 'fi');
UPDATE player_crosses_open_play           SET player_name  = REPLACE(player_name,  'ﬁ', 'fi');
UPDATE player_in_possession_distributions SET player_name  = REPLACE(player_name,  'ﬁ', 'fi');
UPDATE player_line_breaks                 SET player_name  = REPLACE(player_name,  'ﬁ', 'fi');
UPDATE player_offers_receptions           SET player_name  = REPLACE(player_name,  'ﬁ', 'fi');
UPDATE player_out_of_possession           SET player_name  = REPLACE(player_name,  'ﬁ', 'fi');
UPDATE player_physical_data               SET player_name  = REPLACE(player_name,  'ﬁ', 'fi');

UPDATE passing_network_edges              SET from_player  = REPLACE(from_player,  'ﬁ', 'fi');
UPDATE passing_network_edges              SET to_player    = REPLACE(to_player,    'ﬁ', 'fi');

-- VERIFY: should return 8
-- SELECT COUNT(*) FROM matches WHERE "group" LIKE '%final%';


-- =====================================================================
-- FIX 2: Uzbekistan players carried Ghana's country code
-- =====================================================================
-- PROBLEM
-- Match 2026-M047-POR-GHA is labelled Portugal v Ghana, but `matches` records
-- it as Portugal 5-0 Uzbekistan (Group K) and the 26 away-squad names are all
-- Uzbek. Ghana's four actual fixtures are M021, M045, M068, M087.
--
-- The ID codes for that one fixture were generated with GHA instead of UZB,
-- so every Uzbek player got a SECOND identity:
--     UZB_abdukodir_khusanov   (M024, M072)
--     GHA_abdukodir_khusanov   (M047)
--
-- Effect: 26 players split across two IDs. Uzbekistan showed 37 players who
-- appeared (every other squad ~25), and per-player totals were halved --
-- Khusanov read 90 or 180 minutes instead of 270. team_id also read 'GHA',
-- which joins to Ghana in the `teams` table.
--
-- DISCRIMINATOR
-- The `team` column was NOT corrupted -- it correctly says 'Uzbekistan' on
-- every bad row. So `team='Uzbekistan' AND player_id LIKE 'GHA_%'` isolates
-- exactly 26 players with ZERO overlap against the 26 genuine Ghana IDs.
--
-- ORDER MATTERS
-- `players` has no `team` column, so its 52 GHA_ rows cannot be told apart on
-- their own -- they are only identifiable via match_appearances. So `players`
-- is cleaned FIRST, before the evidence is rewritten.
--
-- All 26 bad IDs already had a UZB_ twin, so this is a MERGE: the duplicate
-- `players` rows are deleted, not renamed.
--
-- match_id / match_team_id / appearance_id still contain "GHA" for this
-- fixture. Left alone deliberately: they are opaque keys, consistent across
-- all tables, and renaming them touches 19 tables for no analytical gain.
--
-- Backup taken as PlayerDB_before_uzb_fix.db before running.
-- =====================================================================

-- 1. players FIRST -- delete the 26 duplicates (UZB_ twins already exist)
DELETE FROM players
WHERE player_id IN (
    SELECT DISTINCT player_id FROM match_appearances
    WHERE match_id = '2026-M047-POR-GHA' AND team = 'Uzbekistan'
);

-- 2. remap IDs in every table carrying player_id + team
--    'UZB_' || SUBSTR(player_id,5)  strips the 4-char 'GHA_' prefix
UPDATE match_appearances                  SET player_id='UZB_'||SUBSTR(player_id,5), team_id='UZB' WHERE team='Uzbekistan' AND player_id LIKE 'GHA_%';
UPDATE player_events                      SET player_id='UZB_'||SUBSTR(player_id,5), team_id='UZB' WHERE team='Uzbekistan' AND player_id LIKE 'GHA_%';
UPDATE attempts_at_goal                   SET player_id='UZB_'||SUBSTR(player_id,5), team_id='UZB' WHERE team='Uzbekistan' AND player_id LIKE 'GHA_%';
UPDATE player_in_possession_distributions SET player_id='UZB_'||SUBSTR(player_id,5), team_id='UZB' WHERE team='Uzbekistan' AND player_id LIKE 'GHA_%';
UPDATE player_out_of_possession           SET player_id='UZB_'||SUBSTR(player_id,5), team_id='UZB' WHERE team='Uzbekistan' AND player_id LIKE 'GHA_%';
UPDATE player_line_breaks                 SET player_id='UZB_'||SUBSTR(player_id,5), team_id='UZB' WHERE team='Uzbekistan' AND player_id LIKE 'GHA_%';
UPDATE player_offers_receptions           SET player_id='UZB_'||SUBSTR(player_id,5), team_id='UZB' WHERE team='Uzbekistan' AND player_id LIKE 'GHA_%';
UPDATE player_crosses_open_play           SET player_id='UZB_'||SUBSTR(player_id,5), team_id='UZB' WHERE team='Uzbekistan' AND player_id LIKE 'GHA_%';
UPDATE player_physical_data               SET player_id='UZB_'||SUBSTR(player_id,5), team_id='UZB' WHERE team='Uzbekistan' AND player_id LIKE 'GHA_%';

-- 3. passing_network_edges has two ID columns
UPDATE passing_network_edges SET from_player_id='UZB_'||SUBSTR(from_player_id,5) WHERE team='Uzbekistan' AND from_player_id LIKE 'GHA_%';
UPDATE passing_network_edges SET to_player_id  ='UZB_'||SUBSTR(to_player_id,5)   WHERE team='Uzbekistan' AND to_player_id   LIKE 'GHA_%';
UPDATE passing_network_edges SET team_id='UZB' WHERE team='Uzbekistan' AND team_id='GHA';

-- 4. match_teams carried the same contradiction (team_id GHA, name Uzbekistan)
UPDATE match_teams SET team_id='UZB'
WHERE match_id='2026-M047-POR-GHA' AND team_name='Uzbekistan' AND team_id='GHA';

-- VERIFY (all confirmed after running):
--   GHA_ ids on Uzbek rows ......... 0      (was 26)
--   genuine Ghana ids intact ....... 26     (untouched)
--   Uzbekistan players who played .. 23     (was 37)
--   team/team_id contradictions .... 0
--   appearances / starts / goals / minutes UNCHANGED: 3288 / 2288 / 294 / 211556
--   Khusanov ....................... 3 apps, 270 min -- matches external exactly


-- =====================================================================
-- FIX 3: split player identities + dropped substitution records
-- =====================================================================
-- FOUND BY: comparing per-player minutes against players_external, then
-- testing a structural invariant -- substitutions are 1-for-1, so every
-- team-match must have equal ON and OFF counts:
--
--   SELECT match_id, team,
--          SUM(CASE WHEN subbed_on_minutes  IS NOT NULL THEN 1 ELSE 0 END) ons,
--          SUM(CASE WHEN subbed_off_minutes IS NOT NULL THEN 1 ELSE 0 END) offs
--   FROM match_appearances GROUP BY match_id, team HAVING ons <> offs;
--
-- Returned 2 rows, both Colombia, both Jefferson Lerma's matches: an ON
-- event with no partner. Confirmed against published match reports --
-- 60' Richard Rios <-> Jefferson Lerma (M071), 82' same pair (M096).
-- Now returns 0 rows tournament-wide.

UPDATE match_appearances SET subbed_off_minutes='60'
WHERE match_id='2026-M071-COL-POR' AND player_name LIKE '%LERMA%' AND subbed_off_minutes IS NULL;

UPDATE match_appearances SET subbed_off_minutes='82'
WHERE match_id='2026-M096-SUI-COL' AND player_name LIKE '%LERMA%' AND subbed_off_minutes IS NULL;

-- SPLIT IDENTITIES
-- Three players had a second player_id built from a partial name, because one
-- match report printed the surname or forename alone:
--     FRA_dembele  "DEMBELE"    ==  FRA_ousmane_dembele        "Ousmane DEMBELE"
--     MAR_ounahi   "OUNAHI"     ==  MAR_azzedine_ounahi        "Azzedine OUNAHI"
--     NED_crysencio "Crysencio" ==  NED_crysencio_summerville  "Crysencio SUMMERVILLE"
--
-- TEST USED (this matters -- it is what prevents a wrong merge):
--   two IDs are the SAME player only if they never appear in the same match
--   AND share shirt number and position.
--     overlap 0, same #7  FW  -> Dembele    MERGE
--     overlap 0, same #8  MF  -> Ounahi     MERGE
--     overlap 0, same #24 FW  -> Summerville MERGE
--     overlap 5 matches       -> BRA_danilo / BRA_danilo_santos    DO NOT MERGE
--     overlap 5 matches       -> BRA_ederson / BRA_ederson_silva   DO NOT MERGE
--   Brazil genuinely fielded two Danilos and two Edersons. Name similarity
--   alone would have merged them and silently destroyed four players' stats.
--
--   DELETE FROM players WHERE player_id='<dup>';
--   UPDATE <every table with player_id> SET player_id='<keep>', player_name='<full name>'
--     WHERE player_id='<dup>';
--   (plus from_player_id / to_player_id in passing_network_edges)
--
-- RESULT
--   substitution imbalances .......... 2 -> 0
--   players .......................... 1251 -> 1248  (= external's 1248 exactly)
--   PlayerStats rows ................. 1042 -> 1039  (= external's 1039 exactly)
--   minutes .......................... 211556 -> 211488
--   appearances / starts / goals ..... 3288 / 2288 / 294  UNCHANGED
--   Lerma 480 -> 412, Ounahi 5->6 apps, Dembele 7->8 apps, Summerville 3->4 apps

-- =====================================================================
-- KNOWN REMAINING VARIANCE vs players_external  (not bugs -- documented)
-- =====================================================================
-- 1. THE +/-1 MINUTE CONVENTION  (~640 players, nets to near zero)
--    The two sources disagree over who owns the minute a substitution
--    happens in. A swap at 76':  PlayerDB gives outgoing 76 / incoming 14;
--    external gives 75 / 15. Both total 90.
--    Proof: players never substituted agree 98% of the time, and half-time
--    subs (no shared minute -- the break falls between minutes) agree 9/9.
--    Neither is wrong. No fix.
--
-- 2. TWELVE INDIVIDUAL OUTLIERS  (>5 min, largest: Embolo -53, E.Fernandez -31)
--    Same appearance counts, differing minutes. Not the structural bug --
--    the ON/OFF invariant passes for all of them, and Switzerland used all
--    6 legal extra-time subs in Embolo's disputed match, supporting PlayerDB.
--    Each needs an individual match report to adjudicate. Left as-is.
--
-- CURRENT AGREEMENT: 916 matched players, 275 exact, 93.3% within +/-3 min,
-- net difference -87 minutes across the tournament.


-- =====================================================================
-- FIX 4: misattributed own goal -- IN players_external, not PlayerDB
-- =====================================================================
-- METHODOLOGICAL NOTE, read this first:
-- Editing a validation source so it agrees with the primary source is
-- normally illegitimate -- it destroys the independence that makes the
-- second source worth having. This correction is allowed ONLY because the
-- error was adjudicated against a THIRD piece of evidence that neither
-- source controls, not because agreement was the goal.
--
-- THE ERROR
-- players_external credited Qatar's Boualem Khoukhi with 1 goal.
-- That goal was Miro Muheim's (Switzerland) own goal, M008-QAT-SUI, 95'.
--
-- EVIDENCE THAT PlayerDB IS RIGHT AND players_external IS WRONG:
--   1. matches table:  Qatar 1 - 1 Switzerland. Qatar's only goal in the tie.
--   2. player_events:  records it as event_type='own_goal', player Muheim.
--   3. attempts_at_goal: Khoukhi took ZERO shots in that match. He could
--      not have scored it.
--   4. Arithmetic: PlayerDB 294 player goals + 14 own goals = 308, which
--      equals SUM(home_score+away_score) across all 104 matches.
--      players_external had 295 + 13 = 308 -- same total, one goal moved
--      from the own-goal column into a player's tally.
--
-- The scorelines are independent of both player-level sources, which is
-- what makes this an adjudication rather than a fudge.
--
-- SCOPE: one goal touches nine columns, because FBref-style exports carry
-- pre-computed derived stats. Changing `goals` alone would leave the row
-- internally inconsistent (goals=0 but goals_per90=0.33).
-- shots / shots_on_target left untouched -- those attempts were real; only
-- the goal attribution was wrong.

UPDATE players_external SET
    goals                    = '0.0',
    goals_assists            = '0.0',
    goals_pens               = '0.0',
    goals_per90              = '0.0',
    goals_assists_per90      = '0.0',
    goals_pens_per90         = '0.0',
    goals_assists_pens_per90 = '0.0',
    goals_per_shot           = '0.0',
    goals_per_shot_on_target = '0.0'
WHERE player = 'Boualem Khoukhi';

UPDATE players_external SET own_goals = '1.0'
WHERE player = 'Miro Muheim';

-- VERIFIED AFTER:
--   external goals ....... 295 -> 294   (= PlayerDB)
--   external own_goals .... 13 -> 14    (= PlayerDB)
--   goals + own goals ......... 308     (= sum of all scorelines)
--   per-team goals: all 48 teams agree between sources

-- =====================================================================
-- KNOWN COSMETIC DIFFERENCE (deliberately not "fixed")
-- =====================================================================
-- The two sources spell two team names differently:
--     PlayerDB "Bosnia and Herzegovina"  ==  external "Bosnia-Herz"
--     PlayerDB "USA"                     ==  external "United States"
-- Goal totals for both are identical, so this is naming only. Any join
-- between the sources on team name must alias these two, or those squads
-- silently drop out.
