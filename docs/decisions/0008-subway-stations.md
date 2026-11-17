# ADR-0008: Subway stations come from a bundled MTA list, drawn by us

*Status: proposed — 2026-11-16. Adds a data source alongside ADR-0002's Apple frameworks.*

## Context

Living without a car is the point of the search. If a building isn't easy to reach by subway, nothing
else about it matters. On the 3D map, though, MapKit draws stations as small grey icons among
thousands of other places. Its station markers can't be enlarged or restyled, and MapKit has no
subway line data to style them with. Jon, 2026-11-16: "If we can't use public transportation easily
this is all for naught."

## Decision

1. **The station list is a snapshot bundled in the app.** It comes from New York State's open dataset
   *MTA Subway Stations* (`https://data.ny.gov/resource/39hk-dx4f.json`, 496 stations), which gives
   each station's complex, name, daytime routes and coordinate. It's a JSON resource in
   `UrbaneLibrary`, committed with its source URL and the date it was fetched. The app never fetches
   it. That means no account, no API key, and no requests against MapKit's budget. Subway stations
   change rarely, and Urbane only lasts about six months, so there's no refresh mechanism. Re-fetching
   by hand is enough if it's ever needed.
2. **One marker per station complex.** Rows that share a `complex_id` collapse into one marker that
   carries all their routes. Times Sq-42 St is one marker with 1 2 3 7 A C E N Q R S W. The 496 rows
   collapse to 445 markers.
3. **We draw the markers ourselves, in the MTA's line colors.** Apple's own transit points of interest
   are hidden on maps that show ours, so no station appears twice.
4. **The station list isn't data we own.** It isn't a table and doesn't sync (ADR-0005 is unchanged).
   It's reference data, like the five commute destinations in code.

## Consequences

- Station names and routes are as of the snapshot date. Service changes, such as weekend reroutes,
  aren't shown. Neither are night-only routes: the snapshot has daytime routes only.
- Distance to a station is a straight line, labeled as such. Walking ETAs would cost MapKit requests,
  and the transit commute times (S6) already cover real trips.
