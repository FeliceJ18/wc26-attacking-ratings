SELECT player_name, is_starter, subbed_on_minutes, subbed_off_minutes, ma.match_id,
-- need to replace null data (Coalesce) and strings as integers (Cast)
-- limitation on actual clock minutes per match, db does not include full match lengths including stoppage, better to use conventional measurements to cap regulation games to 90 and ET games to 120 minutes per match, calculating match length per data on events registered in stoppage time would bias data for matches that had stoppage time but no registered events in DB
	MIN(
	CAST(coalesce(subbed_off_minutes, ml.match_length)AS INTEGER),
	coalesce(CAST(red_card_minutes AS INTEGER), ml.match_length)
	) -
	MIN(
	CAST(coalesce(subbed_on_minutes, 0)AS INTEGER),
	ml.match_length
	)
	as minutes
FROM match_appearances ma
-- Left with data on minutes per match assuming each match = 90 minutes, need passes to filter correct minutes per match
JOIN (SELECT match_id, MAX(m) AS last_min, Case WHEN max(m)>= 105 then 120 else 90 end as match_length 
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
ORDER by last_min DESC) as ml
	ON ma.match_id = ml.match_id
WHERE appeared = 'True'
order by minutes desc
