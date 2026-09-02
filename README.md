# 2026 World Cup Attacking Ratings Project
By John Felice

**[View the interactive dashboard on Tableau Public](https://public.tableau.com/app/profile/john.felice/viz/2026WorldCupAttackingRatings/RatingDashboard)**

## Goal: Use data to build a model illustrating most dangerous attacking players at 2026 World Cup.
- Illustrate: Player profiles, positions, & attacking impact based on generation & output stats

## Model: 
- 301 outfield players with 270+ minutes, goalkeepers excluded
- Two axes: output (goals + assists) and generation (take-ons, last line breaks, offensive movements)
- Metrics chosen by testing all 70 numeric columns against goals/assists/shots, finding correlation between generative actions and output
- Regression to the mean shrinkage so 3 contributions in 3 matches doesn't outrank 12 in 8 when measuring per90 impact
- Scaled rather than ranked, percentiles compressed every good player into 95–100; 100 = the best rate in the tournament, 50 = half that

## Findings:
- Yamal and Haaland at opposite corners, pure generation winger and pure output efficient striker; shows players with high specialization effect on team attacking danger
- Doku and Yamal are the same on ball archetype, Vinícius and Olise rates high through balance on & off the ball
- Attacking fullbacks surface, Hakimi in the top 10% of all outfielders, modern attacks rely on impact from generative fullbacks; Dest & Mendes
- USA breakout talents Tillman and Balogun reach similar ratings by opposite routes, one a passer, one a runner
- Similarly we see our top rated players separated from the rest in their own attacking league, Messi & Mbappe, also with different profiles but elite output and generation broken down by how they did it

## Method: 03_player_ratings.sql
Used data on 2026 World Cup acquired publicly through Kaggle (Listed in sources). Primary dataset including 21 CSV tables with over 95k rows. 
- First task to use data points to calculate needed player appearances & minutes as well as match length for project. 
- Calculated minutes based on match event and substitution data (minutes = minute_they_left − minute_they_entered)
- Match length / Extra time not labelled in data, inferred from latest match event data whether match ended in regulation or ET
    - Validated: Emiliano Martínez comes out at exactly 810 = 5×90 + 3×120, matching Argentina's three extra-time games
- Validated data with secondary source after entity resolution
- Used data to build queried table tracking relevant attacking player data, plotting on Tableau for visual findings

Imported Primary & External CSVs, compared, validated
Data cleaning sql to fix data errors and confirm validation
Name key for entity resolution and to be able to use data from external
Player match map to finalize unresolved entity resolution using blocking
Manual corrections for decided exclusions and filters for model (Playoff match)
Final Player Rating query & table


## Data Quality: 00_data_cleaning.sql, 04_manual_corrections.sql qa/integrity_checks.sql
- PDF ligature: "fi" stored as one character in 422 rows. Replaced in player names and knockout "final" matches.
- Wrong country codes: Portugal v Uzbekistan was recorded under Ghana's code, splitting all 26 Uzbek players across two IDs and halving their totals
- Split identities: three players had a second ID from a partial name. Verified by blocking team, match appearances, & minutes per player, which also proved Brazil's two Danilos were genuinely two players and must not be merged
- Dropped substitutions: found by a structural check, substitutions are 1-for-1, so ON and OFF counts must balance per team per match. Two didn't, both Lerma's, confirmed against match reports
- Misattributed goal: an own goal credited to the wrong player in the second source, caught because both sources summed to 308 against the scorelines
- Second-yellow dismissals not recorded. The tournament had 15 sendings off with 13 straight reds appearing in the red card column. 
    - The two second yellows exist solely as a two-value yellow-card string with nothing marking them as dismissals, causing both players to be credited with the remainder of matches they'd been sent off from. Both were extra-time games, costing 51 and 27 minutes. Correcting it brought the two sources into exact agreement on total minutes.
    - Embolo and Fernández's missing minutes were resolved by recognising that both had received two yellows in a match, which the data never labels as a dismissal


## Entity Resolution
- Second source had names only, no IDs, and the two spelled names differently whether in translation, accents, or nicknames 
- Rule-based key (accents, punctuation, spacing) got 969 of 1,039
- The last 70 needed judgment; matched on team + appearances + minutes rather than name, which is the only thing that resolves MOHAMMAD ABUZRAIQ = Sharara
- Defined Parameters and Blocks to run agent for entity resolution and table updating: 00_data_cleaning 01_unmatched_pairs 02_player_match_map build_name_key

## Limitations:
- No chance-creation data; model used defensive line breaks, the final ball, correlating +0.25 with assists
- Third-place playoff excluded; Match produced 10 goals against a tournament average of 3 in a fixture with no trophy and rotated squads. Generates data by a different process than the other 103.
    - Excluding it meant 17 goal contribution data points are left off, most notably affecting players like Bukayo Saka who without this match loses his entire output catalog and minute requirement. 
    - Assists from this match had to be removed by hand, as the second source records assists only as tournament totals with no match breakdown.
- No player-level xG or xA, so no over/underperformance measure
- Defenders are included deliberately and rate low, because this measures attacking danger, not quality
- Minutes now reconcile exactly with the second source, both totaling at 211,410. The residual per-player differences are a convention disagreement over who owns the minute a substitution occurs in (a swap at 76' gives the outgoing player 76 and the incoming 14 in one source, 75 and 15 in the other; both sum to 90). Twelve players still differ by 6–8 minutes with no third source to adjudicate.


## Sources: 
Primary- https://www.kaggle.com/datasets/heshamelalamy47/worldcup-2026-open-data-1-47-million-data-points
Validation/Assist source- https://www.kaggle.com/datasets/swaptr/fifa-wc-2026-players
