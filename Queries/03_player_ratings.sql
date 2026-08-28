-- =====================================================================
-- 06_player_ratings.sql  |  the two chart axes
-- =====================================================================
-- One row per outfield player with 270+ minutes (301 rows).
--
--   output_rating      Y axis -- goals + assists per 90
--   generation_rating  X axis -- the three generation dimensions, aggregated
--   overall_rating     the mean of the two axes
--
-- All three are SCALED RATES on 0-100, not percentiles. 100 is the best rate
-- in the population; 50 is half that rate. A rating is NOT "top X percent".
-- Raw totals are kept for tooltips; the per-90 rates and per-metric scales are
-- built as intermediates and not emitted.
--
-- overall_rating tops out at 91, not 100, because no single player led both
-- axes -- Mbappe is 100 for output but 83 for generation, Yamal is 100 for
-- generation but 10 for output. That ceiling is information, not a bug.
--
-- =====================================================================
-- SECOND-YELLOW DISMISSALS
-- =====================================================================
-- The tournament had 15 sendings off: 13 straight reds and 2 second yellows.
-- Only the 13 straight reds appear in red_card_minutes. The two second
-- yellows exist ONLY as a two-value yellow_card_minutes string and nothing
-- in the data marks them as dismissals:
--     Breel EMBOLO      M100-ARG-SUI   yellows "44 69"  -> off at 69
--     Enzo FERNANDEZ    M104-ESP-ARG   yellows "82 93"  -> off at 93
--
-- Both matches went to extra time, so each player was being credited with a
-- full 120 minutes. Handling it closes the last gap against the second
-- source exactly:
--     total minutes   211488 -> 211410   (external: 211410, difference 0)
--     Embolo  554 -> 503   external 501
--     Fernandez 690 -> 663 external 659
-- 51 + 27 = 78, which was the entire net minutes gap between the sources.
--
-- =====================================================================
-- EXCLUDED: THE THIRD-PLACE PLAYOFF  (2026-M103-FRA-ENG)
-- =====================================================================
-- France 4-6 England produced 10 goals against a tournament average of
-- 2.96 per match -- 3.4 times the normal rate from 1 of 104 fixtures.
--
-- The justification is not the scoreline, it is that the fixture generates
-- data by a different process: no trophy, rotated squads, lower intensity.
-- The 10 goals are the symptom.
--
-- Leaving it in distorts individual players badly:
--     Bukayo SAKA      3 of 3 goals   100 percent of his tournament record
--     Declan RICE      1 of 1         100 percent
--     Ezri KONSA       1 of 1         100 percent
--     Bradley BARCOLA  1 of 3          33 percent
--     Kylian MBAPPE    2 of 10         20 percent
--
-- Saka rated 95 for output on goals scored entirely in a dead rubber.
--
-- COST OF THIS DECISION, stated rather than buried: 32 appearances are
-- removed and 2 players fall below the 270-minute threshold (303 -> 301).
-- Saka drops sharply, which anyone who watched the tournament will notice.
-- Delete the match_id line in `totals` to put it back.
--
-- =====================================================================
-- HOW THE RATINGS ARE BUILT, AND WHY
-- =====================================================================
-- OUTPUT: goals and assists are summed FIRST, then turned into one rate.
-- It is deliberately not the average of a goals score and an assists score --
-- that method scores a player zero on whichever component they lack, so
-- Michael Olise (5 assists, 0 goals) took a hard zero on part of his score
-- and ranked 16th instead of 6th. Summing first lets a pure creator and a
-- pure finisher reach the same output rating by different routes.
--
-- GENERATION: each component is scaled to 0-100 FIRST, then averaged. They
-- cannot be summed raw -- pressing runs at roughly ten times the volume of
-- take-ons, so a raw sum would just rank players by pressing.
--
-- SHRINKAGE, then SCALE. Two separate fixes, both needed:
--
--   SHRINKAGE answers "should I believe this rate?" Each rate gets a prior
--   worth 3 matches of average production added to it:
--       adjusted = (events + 3 * population_rate) / (n90 + 3)
--   A big sample overwhelms the prior; a small one cannot. Messi (12 G+A in
--   8.2 matches) moves 1.46 -> 1.14, Vargas (3 in 3.1) moves 0.96 -> 0.61.
--   Side effect worth knowing: this removes the hard zero. Previously 153
--   players sat at exactly 0 output and formed a stripe along the chart floor.
--   It also means that among players with no goals or assists, MORE minutes
--   gives a slightly LOWER rating -- zero in 8 matches is stronger evidence
--   of low production than zero in 3. Correct, occasionally surprising.
--
--   SCALE answers "by how much?" Values are stretched linearly onto 0-100
--   rather than ranked. PERCENT_RANK was used here originally and destroyed
--   the distances: Mbappe produces 70 percent more per 90 than Vargas, but
--   ranked they came out 100 and 95, because near the top there is almost
--   nobody left to pass and everyone good compresses into 95-100 -- exactly
--   where a most-dangerous chart needs its resolution.
--   The cost, accepted deliberately: 50 no longer means the median player,
--   it means half the best rate. Both axes are skewed as a result, which is
--   the honest shape -- goal contribution really is that rare.
--
-- READING THE CHART
--   top-right     high generation, high output -- the best players
--   bottom-right  created danger, no end product
--   top-left      output from very little
--   bottom-left   neither
--
-- NO output-minus-generation COLUMN, on purpose. It looks like a measure of
-- clinical finishing and is not. Three things are tangled in that gap:
-- the player's own finishing, their TEAMMATES' finishing (an assist needs
-- someone else to score), and the actual quality of what they created.
-- The standard version of this metric works because it is measured against
-- xG/xA -- expected goals from the chances generated. Generation here is
-- activity (take-ons, presses, runs), not chance quality, so the gap would
-- mostly rank players by conversion luck over 5-8 matches and would punish
-- a creator whose teammates missed. Neither source has player-level xG, so
-- that separation is not available. The scatter still shows the same
-- information visually, but with the absolute levels visible alongside it.
--
-- =====================================================================
-- POPULATION
-- =====================================================================
--   Goalkeepers excluded: zero on every attacking metric, they would anchor
--   the bottom of every scale.
--   Defenders INCLUDED deliberately -- this measures attacking danger, not
--   overall quality, so a centre-back rating low is a correct result, and it
--   lets attacking fullbacks stand out (Hakimi, Cancelo, Nuno Mendes).
--   Scales run across the whole population, NOT within position, so a
--   fullback rating is directly comparable to a striker rating.
--   Minimum 270 minutes = three full matches = a complete group stage.
--   Below ~90 minutes rates become nonsense: one goal in two minutes reads
--   as 45 goals per 90.
--
--   About half the population has zero goals AND zero assists (mostly
--   defenders), so half of them sit at the bottom of output_rating. That is
--   real -- most outfielders at a World Cup produce nothing -- and the chart
--   needs to handle that band rather than hide it.
--
-- =====================================================================
-- WHY THESE FOUR GENERATION METRICS
-- =====================================================================
-- Every numeric column in the database was tested against goals, assists
-- and shots per 90.
--
--   take_ons            beating a man one-v-one          shots +0.40
--   def_line_breaks     passes through the last line     assists +0.25
--   attacking_movement  runs behind + between the lines  (G+A)/90 +0.57
--   pressing_indirect   pressing (nobody scores zero)    shots +0.50
--
-- All four skew FW/MF; none is a defender metric.
--
-- THEY ARE COMBINED AS THREE DIMENSIONS, NOT FOUR. Correlations between the
-- four components across the 301 players:
--                take_ons   def_lb  movement  pressing
--   take_ons         1.00     0.43      0.43      0.42
--   def_lb           0.43     1.00      0.45      0.40
--   movement         0.43     0.45      1.00      0.77   <--
--   pressing         0.42     0.40      0.77      1.00   <--
--
-- movement and pressing are 0.77 correlated -- this data cannot tell the two
-- apart, whatever they measure conceptually -- so they are averaged into one
-- off-ball-work term worth a third, rather than taking half the score between
-- them. The result: beating a man, breaking the last line, off-ball work.
--
-- This LOWERS generation-vs-output correlation from +0.50 to +0.45, which is
-- the point. If generation predicted output the scatter would collapse to a
-- diagonal and show nothing; the chart works because the axes are related but
-- distinct. The shift moves the axis from rewarding work rate toward
-- rewarding on-ball skill -- Lautaro Martinez (98 movement, 98 pressing, but
-- 53 take-ons and 17 line breaks) falls from 27th to 41st, Messi (96, 98 on
-- the on-ball pair) rises from 10th to 4th.
--
-- ATTACKING MOVEMENT combines in_behind and in_between. The six movement
-- types (in_behind, in_between, in_front, out_to_in, in_to_out, no_movement)
-- sum EXACTLY to total_offers, so every offer is classified as exactly one
-- type -- they are mutually exclusive and adding two does not double-count.
-- Measured against (G+A) per 90:
--     in_behind alone              +0.516
--     in_between alone             +0.455
--     in_behind + in_between       +0.572   <- kept
-- Together they capture attacking movement more completely than either.
--
-- REJECTED, and why:
--   line_breaks_completed  shots -0.33 -- 48 of the top 50 are DF/MF. As a
--       single column it is dominated by defenders playing out from the back.
--       The signal only appears once you split by WHICH line was broken:
--           defensive-line breaks  assists +0.25  (the final ball)
--           midfield-line breaks   assists +0.02  (progression)
--           attacking-line breaks  assists -0.27  (beating a press, 43/50 DF)
--       Lines are named from the OPPONENT perspective -- their attacking line
--       is their forwards, so breaking it means playing out from defence.
--   step_ins               shots -0.01 -- carrying past opponents, but almost
--       all of it happens in build-up. 27 of the top 50 are defenders.
--   ball_progressions      shots +0.44 -- real, but Doku/Yamal/Vinicius top
--       both this and take_ons. Including both double-counts dribblers.
--   crosses_completed      assists +0.27 -- best raw assist link, but 143 of
--       303 players never cross, so it scores nearly half the population at
--       zero and punishes central players for a job they do not have.
--
-- def_line_breaks sums the two/three/four-unit defensive-line columns (4124
-- events). two_units_defensive_line alone scores higher against assists
-- (+0.32) but on only 1589 events, so that gain is probably sample noise.
--
-- A line break is overwhelmingly a PASS: 24973 of 27287 attempts, against
-- 1533 ball carries and 781 crosses.
-- =====================================================================

WITH match_length AS (
    SELECT match_id,
           CASE WHEN MAX(m) >= 105 THEN 120 ELSE 90 END AS match_length
    FROM (SELECT match_id, minute AS m                                   FROM player_events
          UNION ALL SELECT match_id, minute                              FROM attempts_at_goal
          UNION ALL SELECT match_id, CAST(subbed_off_minutes AS INTEGER) FROM match_appearances
          UNION ALL SELECT match_id, CAST(subbed_on_minutes  AS INTEGER) FROM match_appearances)
    GROUP BY match_id
),
-- The third-place playoff is excluded below, which removes its goals but
-- cannot remove its assists -- players_external carries assists as a
-- per-player tournament total with no match breakdown, and PlayerDB holds
-- no assist records at all. The seven assists from that match were read off
-- the published match report and live in the table manual_playoff_assists,
-- which is joined in the rates CTE and subtracted.
--
-- They are NOT written into player_events on purpose: every other event type
-- there is complete for all 104 matches, so assist rows for a single fixture
-- would make assist the only 1-of-104 type, and the first person to
-- COUNT(*) it would conclude the tournament had seven assists.
-- See Queries/07_manual_corrections.sql for the table and its provenance.
totals AS (
    SELECT p.player_id, p.display_name, p.name_key,
           MIN(ma.team)                                          AS team,
           MIN(ma.position)                                      AS position,
           SUM(CASE WHEN ma.appeared = 'True' THEN 1 ELSE 0 END) AS appearances,
           SUM(CASE WHEN ma.is_starter='True' THEN 1 ELSE 0 END) AS starts,
           SUM( MIN( CAST(COALESCE(ma.subbed_off_minutes, ml.match_length) AS INTEGER),
                     ml.match_length,
                     -- dismissal: a straight red, OR a second yellow. This data
                     -- records only straight reds in red_card_minutes -- the two
                     -- second-yellow sendings off appear ONLY as a two-value
                     -- yellow_card_minutes string ("44 69"), with nothing marking
                     -- them as dismissals. Without this the player is credited with
                     -- the rest of a match he was sent off from.
                     COALESCE( CAST(ma.red_card_minutes AS INTEGER),
                               CASE WHEN INSTR(ma.yellow_card_minutes, ' ') > 0
                                    THEN CAST(SUBSTR(ma.yellow_card_minutes,
                                              INSTR(ma.yellow_card_minutes, ' ') + 1) AS INTEGER)
                               END,
                               ml.match_length ) )
              - MIN( CAST(COALESCE(ma.subbed_on_minutes, 0) AS INTEGER),
                     ml.match_length ) )                         AS minutes,
           SUM(dist.goals)                                       AS goals,
           SUM(dist.take_ons)                                    AS take_ons,
           SUM(ofr.in_behind + ofr.in_between)                   AS attacking_movement,
           SUM(oop.pressing_indirect)                            AS pressing,
           SUM(  lb.two_units_defensive_line
               + lb.three_units_defensive_line
               + lb.four_units_defensive_line)                   AS def_line_breaks
    FROM players p
    JOIN match_appearances ma ON ma.player_id = p.player_id
    JOIN match_length ml      ON ml.match_id  = ma.match_id
    LEFT JOIN player_in_possession_distributions dist ON dist.appearance_id = ma.appearance_id
    LEFT JOIN player_line_breaks                 lb   ON lb.appearance_id   = ma.appearance_id
    LEFT JOIN player_offers_receptions           ofr  ON ofr.appearance_id  = ma.appearance_id
    LEFT JOIN player_out_of_possession           oop  ON oop.appearance_id  = ma.appearance_id
    WHERE ma.appeared = 'True'
      AND ma.position <> 'GK'
      AND ma.match_id <> '2026-M103-FRA-ENG'   -- third-place playoff, see header
    GROUP BY p.player_id
    HAVING minutes >= 270
),
rates AS (
    -- raw counts plus n90 (matches played). Rates are built in the next step.
    SELECT t.*, e.age, e.club,
           t.minutes / 90.0                                                     AS n90,
           MAX(COALESCE(CAST(e.assists AS REAL),0) - COALESCE(pa.assists,0), 0) AS assists
    FROM totals t
    LEFT JOIN player_match_map m ON m.player_id = t.player_id
    LEFT JOIN players_external e ON e.name_key  = COALESCE(m.external_name_key, t.name_key)
                                AND e.minutes IS NOT NULL
    LEFT JOIN manual_playoff_assists pa ON pa.name_key = e.name_key
),
shrunk AS (
    -- SHRINKAGE. Each rate is pulled toward the population average by adding
    -- a prior worth 3.0 matches of average production:
    --     adjusted = (events + C * population_rate) / (n90 + C)
    -- A large sample overwhelms the prior and barely moves; a small one cannot.
    -- Messi (12 G+A in 8.2 matches) goes 1.46 -> 1.14, while Vargas (3 in 3.1)
    -- goes 0.96 -> 0.61. Without this, three contributions in three matches
    -- rates alongside twelve in eight.
    -- The population rate is computed with SUM() OVER () -- the total across
    -- every player in the window, not per row.
    SELECT r.*,
           ((r.goals + r.assists)  + 3.0 * (SUM(r.goals + r.assists)  OVER () / SUM(r.n90) OVER ())) / (r.n90 + 3.0) AS ga_adj,
           (r.take_ons            + 3.0 * (SUM(r.take_ons)            OVER () / SUM(r.n90) OVER ())) / (r.n90 + 3.0) AS take_ons_adj,
           (r.def_line_breaks     + 3.0 * (SUM(r.def_line_breaks)     OVER () / SUM(r.n90) OVER ())) / (r.n90 + 3.0) AS def_lb_adj,
           (r.attacking_movement  + 3.0 * (SUM(r.attacking_movement)  OVER () / SUM(r.n90) OVER ())) / (r.n90 + 3.0) AS att_move_adj,
           (r.pressing            + 3.0 * (SUM(r.pressing)            OVER () / SUM(r.n90) OVER ())) / (r.n90 + 3.0) AS pressing_adj
    FROM rates r
),
scaled AS (
    -- SCALE, not rank. Each adjusted rate is stretched linearly onto 0-100:
    --     100 * (x - min) / (max - min)
    -- so the DISTANCE between players survives. PERCENT_RANK was used here
    -- before and destroyed it: Mbappe produces 70 percent more per 90 than
    -- Vargas, but ranked they were 100 and 95, because near the top there is
    -- almost nobody left to pass and everyone good compresses into 95-100 --
    -- exactly where a most-dangerous chart needs resolution.
    -- Cost: 50 now means half the best rate, not the median player.
    SELECT k.*,
           100.0 * (ga_adj       - MIN(ga_adj)       OVER ()) / (MAX(ga_adj)       OVER () - MIN(ga_adj)       OVER ()) AS output_s,
           100.0 * (take_ons_adj - MIN(take_ons_adj) OVER ()) / (MAX(take_ons_adj) OVER () - MIN(take_ons_adj) OVER ()) AS take_ons_s,
           100.0 * (def_lb_adj   - MIN(def_lb_adj)   OVER ()) / (MAX(def_lb_adj)   OVER () - MIN(def_lb_adj)   OVER ()) AS def_lb_s,
           100.0 * (att_move_adj - MIN(att_move_adj) OVER ()) / (MAX(att_move_adj) OVER () - MIN(att_move_adj) OVER ()) AS att_move_s,
           100.0 * (pressing_adj - MIN(pressing_adj) OVER ()) / (MAX(pressing_adj) OVER () - MIN(pressing_adj) OVER ()) AS pressing_s
    FROM shrunk k
),
combined AS (
    -- THREE dimensions, not four. attacking_movement and pressing correlate
    -- 0.77 with each other while every other pair sits near 0.43, so they are
    -- one dimension (off-ball work) and share a single third of the score.
    SELECT c.*,
           ( take_ons_s                          -- beating a man
           + def_lb_s                            -- breaking the last line
           + (att_move_s + pressing_s) / 2.0     -- off-ball work
           ) / 3.0                                                   AS gen_avg
    FROM scaled c
),
stretched AS (
    -- averaging three scaled values pulls the result toward the middle, so
    -- the aggregate is stretched back onto 0-100. Linear, so the spacing
    -- between players is preserved -- only the range changes.
    SELECT g.*,
           100.0 * (gen_avg - MIN(gen_avg) OVER ()) / (MAX(gen_avg) OVER () - MIN(gen_avg) OVER ()) AS generation_s
    FROM combined g
)
SELECT display_name AS player, team, position, age, club,
       appearances, starts, minutes,

       goals, CAST(assists AS INTEGER) AS assists,
       take_ons, def_line_breaks, attacking_movement, pressing,

       ROUND(output_s)     AS output_rating,       -- Y
       ROUND(generation_s) AS generation_rating,   -- X
       ROUND((output_s + generation_s) / 2.0) AS overall_rating
FROM stretched
ORDER BY overall_rating DESC, minutes DESC, player
