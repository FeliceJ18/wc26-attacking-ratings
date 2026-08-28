-- Top 10 highest scoring matches of the 2026 World Cup
SELECT home_score+away_score as total_goals, home_team, away_team, "group" as Stage
FROM matches
Order by total_goals DESC
Limit 10