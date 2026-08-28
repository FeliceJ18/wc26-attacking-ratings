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
ORDER by last_min DESC 