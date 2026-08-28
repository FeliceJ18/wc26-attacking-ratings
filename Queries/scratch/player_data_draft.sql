-- player list, appearances, starts, minutes, relevant stats
-- appearance count inaccurate, substitutes given appearance for each game team has played not individually played
SELECT display_name, player_id, team, sum(CASE WHEN appeared='True' THEN 1 ELSE 0 END) as appearances, 
	sum(CASE WHEN is_starter='True' THEN 1 ELSE 0 END) as starts,
-- need to replace null data (Coalesce) and strings as integers (Cast)
-- limitation on actual clock minutes per match, db does not include full match lengths including stoppage, better to use conventional measurements to cap regulation games to 90 and ET games to 120 minutes per match, calculating match length per data on events registered in stoppage time would bias data for matches that had stoppage time but no registered events in DB
	SUM(MIN(
	CAST(coalesce(subbed_off_minutes, ml.match_length)AS INTEGER),
	coalesce(CAST(red_card_minutes AS INTEGER), ml.match_length)
	) -
	MIN(
	CAST(coalesce(subbed_on_minutes, 0)AS INTEGER),
	ml.match_length
	))
	as minutes
From players p
JOIN match_appearances ma
	USING (player_id)
-- some players with insufficient appearances / minutes data not relevent to desired insights
-- minutes need manual calculation, minutes = minute_they_left − minute_they_entered
JOIN (SELECT match_id, Case WHEN max(m)>= 105 then 120 else 90 end as match_length 
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
	) as ml
	ON ma.match_id = ml.match_id
WHERE appeared = 'True'
group by player_id
order by minutes DESC
