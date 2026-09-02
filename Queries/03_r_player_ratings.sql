-- STAGE 2 DETERMINE MATCH LENGTH
WITH match_length AS (
	SELECT match_id, MAX(m) AS last_min, Case WHEN max(m)>= 105 then 120 else 90 end as match_length 
	From (
		SELECT match_id, minute AS m from player_events
		UNION ALL
		SELECT match_id, minute from attempts_at_goal
		UNION ALL
		SELECT match_id, CAST(subbed_off_minutes AS INTEGER) from match_appearances
		UNION ALL
		SELECT match_id, CAST(subbed_on_minutes AS INTEGER) from match_appearances
		)
Group by match_id
ORDER by last_min DESC)
-- STAGE 1 BUILD A TABLE OF ONE ROW PER PLAYER WITH PLAYER, TEAM, POSITION, APPEARANCES, STARTS, MINUTES.
SELECT  ma.player_id, 
		player_name, 
		MIN(team) AS team, 
		MIN(position) AS position, 
		COUNT(*) AS appearances, 
		SUM(CASE WHEN is_starter='True' THEN 1 ELSE 0 END) AS starts,
		-- STAGE 3 ADDING MINUTES COLUMN FROM EVENTS & MATCH LENGTH
		SUM(MIN(CAST(coalesce(subbed_off_minutes, ml.match_length)AS INTEGER), 
	                coalesce(CAST(red_card_minutes AS INTEGER), ml.match_length), 
					-- SECOND YELLOW = SENT OFF FIX
					coalesce(CASE WHEN INSTR(yellow_card_minutes, ' ') > 0 
						THEN CAST(SUBSTR(yellow_card_minutes, INSTR(yellow_card_minutes, ' ') + 1 ) AS INTEGER) END, ml.match_length))  
		- MIN(CAST(coalesce(subbed_on_minutes, 0)AS INTEGER), ml.match_length)) as minutes
FROM match_appearances ma
JOIN match_length ml ON ml.match_id = ma.match_id
-- FILTERS
WHERE appeared = 'True' AND
      position <> 'GK' AND
	  ma.match_id <> '2026-M103-FRA-ENG'
GROUP BY player_id
HAVING minutes >= 270
ORDER BY minutes DESC	

