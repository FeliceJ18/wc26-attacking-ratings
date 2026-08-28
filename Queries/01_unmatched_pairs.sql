-- Players still unmatched between PlayerDB and players_external, both sides
-- shown together and grouped by team so counterparts sit next to each other.
--
-- UNION ALL stacks two anti-joins: one finds PlayerDB players with no
-- external partner, the other finds external players with no PlayerDB
-- partner. The 'source' column labels which list a row came from.
--
-- Expect 140 rows: 70 from each side. Within a team, a PlayerDB name and an
-- external name that clearly refer to the same person are a pair to record.
-- age and club show only for external rows, PlayerDB has neither, and they
-- are the strongest clues for confirming an uncertain pairing.

SELECT t.team                AS team,
       'A_PlayerDB'          AS source,
       d.display_name        AS name,
       NULL                  AS age,
       NULL                  AS club
FROM players d
JOIN (SELECT player_id, MIN(team) AS team
      FROM match_appearances
      WHERE appeared = 'True'
      GROUP BY player_id) t          ON t.player_id = d.player_id
LEFT JOIN players_external e         ON d.name_key = e.name_key
                                    AND e.minutes IS NOT NULL
WHERE e.player IS NULL

UNION ALL

SELECT CASE e.team
           WHEN 'Bosnia' || CHAR(8211) || 'Herz' THEN 'Bosnia and Herzegovina'
           WHEN 'United States'                  THEN 'USA'
           ELSE e.team
       END,
       'B_external',
       e.player,
       e.age,
       e.club
FROM players_external e
LEFT JOIN (SELECT d.name_key
           FROM players d
           JOIN (SELECT player_id FROM match_appearances
                 WHERE appeared = 'True' GROUP BY player_id) t
             ON t.player_id = d.player_id) d    ON d.name_key = e.name_key
WHERE e.minutes IS NOT NULL
  AND d.name_key IS NULL

ORDER BY team, source, name;
