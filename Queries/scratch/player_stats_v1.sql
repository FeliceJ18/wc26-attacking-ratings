-- =====================================================================
-- player_stats_v1.sql  |  SUPERSEDED -- see 03_player_ratings.sql
-- Kept for reference: it holds the shots-per-100-runs analysis, which the
-- ratings table does not carry. Its population differs (344 rows: includes
-- goalkeepers and the third-place playoff), so its numbers will NOT match
-- the current model.
-- =====================================================================
-- One row per player, totals plus per-90 rates.
--
-- STRUCTURE: the inner query collapses PlayerDB to one row per player.
-- players_external is joined only after that, so both sides are per-player
-- and nothing fans out -- which is why assists needs no aggregate wrapper.
--
-- MINIMUM MINUTES: 270 = three full matches = a complete group stage.
-- Rate stats on tiny samples are meaningless -- one goal in two minutes
-- reads as 45 goals per 90. Change the HAVING below to adjust:
--     no filter -> 1019 players, worst rate 45.0 goals/90  (unusable)
--     90        ->  731 players, worst rate  1.8 goals/90
--     270       ->  344 players, worst rate  1.4 goals/90  (Haaland - real)
--
-- PER-90: computed here rather than taken from players_external, because
-- external has no per-90 for take_ons or line_breaks, and its rates use its
-- own minutes total (211410 vs our 211488). Mixing them would put different
-- denominators in the same row.
-- The 90.0 must stay a decimal -- 90 alone gives integer division and zeros.
--
-- IN-BEHIND: runs made behind the defensive line. Correlates +0.64 with
-- shots/90 and +0.52 with goals/90 across 344 players, so it tracks real
-- threat. Shown per 90 so it does not simply reward minutes played.
-- shots_per_100_runs separates players whose runs produce shots from those
-- who move without threatening.
-- LIMITATION: offers_received is not broken down by movement type, so how
-- often the in-behind runs were actually FOUND cannot be computed.
--
-- TARGETS (before the HAVING filter): rows 1039 | apps 3288 | starts 2288
--   minutes 211488 | goals 294 | assists 224 | take_ons 5399
--   line_breaks 19190 | in_behind 18426
-- =====================================================================

SELECT s.display_name                                   AS player,
       s.team,
       e.age,
       e.club,
       s.appearances,
       s.starts,
       s.minutes,

       s.goals,
       CAST(e.assists AS INTEGER)                       AS assists,
       s.shots,
       s.take_ons,
       s.line_breaks,
       s.in_behind,

       ROUND(s.goals            * 90.0 / s.minutes, 2)  AS goals_p90,
       ROUND(e.assists          * 90.0 / s.minutes, 2)  AS assists_p90,
       ROUND(s.shots            * 90.0 / s.minutes, 2)  AS shots_p90,
       ROUND(s.take_ons         * 90.0 / s.minutes, 2)  AS take_ons_p90,
       ROUND(s.line_breaks      * 90.0 / s.minutes, 2)  AS line_breaks_p90,
       ROUND(s.in_behind        * 90.0 / s.minutes, 2)  AS in_behind_p90,

       -- threat conversion: shots generated per 100 runs in behind.
       -- NULLIF guards the players with zero runs (keepers, most defenders)
       ROUND(s.shots * 100.0 / NULLIF(s.in_behind, 0), 1) AS shots_per_100_runs

FROM (
    SELECT p.player_id,
           p.display_name,
           p.name_key,
           MIN(ma.team)                                                    AS team,
           SUM(CASE WHEN ma.appeared   = 'True' THEN 1 ELSE 0 END)         AS appearances,
           SUM(CASE WHEN ma.is_starter = 'True' THEN 1 ELSE 0 END)         AS starts,
           SUM( MIN( CAST(COALESCE(ma.subbed_off_minutes, ml.match_length) AS INTEGER),
                     COALESCE(CAST(ma.red_card_minutes AS INTEGER), ml.match_length) )
              - MIN( CAST(COALESCE(ma.subbed_on_minutes, 0) AS INTEGER),
                     ml.match_length ) )                                   AS minutes,
           SUM(dist.goals)                                                 AS goals,
           SUM(dist.attempts_at_goal)                                      AS shots,
           SUM(dist.take_ons)                                              AS take_ons,
           SUM(lb.line_breaks_completed)                                   AS line_breaks,
           SUM(ofr.in_behind)                                              AS in_behind
    FROM players p
    JOIN match_appearances ma ON ma.player_id = p.player_id
    JOIN (SELECT match_id,
                 CASE WHEN MAX(m) >= 105 THEN 120 ELSE 90 END AS match_length
          FROM (SELECT match_id, minute AS m                              FROM player_events
                UNION ALL SELECT match_id, minute                         FROM attempts_at_goal
                UNION ALL SELECT match_id, CAST(subbed_off_minutes AS INTEGER) FROM match_appearances
                UNION ALL SELECT match_id, CAST(subbed_on_minutes  AS INTEGER) FROM match_appearances)
          GROUP BY match_id) ml                     ON ml.match_id = ma.match_id
    LEFT JOIN player_in_possession_distributions dist ON dist.appearance_id = ma.appearance_id
    LEFT JOIN player_line_breaks                 lb   ON lb.appearance_id   = ma.appearance_id
    LEFT JOIN player_offers_receptions           ofr  ON ofr.appearance_id  = ma.appearance_id
    WHERE ma.appeared = 'True'
    GROUP BY p.player_id
    HAVING minutes >= 270          -- <-- minimum minutes filter
) s
LEFT JOIN player_match_map m ON m.player_id = s.player_id
LEFT JOIN players_external e ON e.name_key  = COALESCE(m.external_name_key, s.name_key)
                            AND e.minutes IS NOT NULL
ORDER BY s.minutes DESC
