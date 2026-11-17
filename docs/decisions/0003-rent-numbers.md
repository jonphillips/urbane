# ADR-0003: Rent numbers are dated observations from named sources, collected by hand

*Status: proposed — 2026-11-16*

## Context

Jon wants recent 2BR rents on the map. There's no licensed feed, and StreetEasy blocks bots from
servers. Scraping is out of scope. The numbers still need to be honest: rents move, and a number with
no date misleads.

## Decision

1. **Two layers:**
   - **Neighborhood 2BR median asking rent**, monthly, from StreetEasy's public Data Dashboard
     download. Imported from a CSV file Jon downloads, by a small importer in Settings. Shown as the
     current value plus a 12-month sparkline.
   - **Building observations**: one row per known 2BR rental (rent, unit if known, square feet if
     known, the date seen, and the source URL). Captured from the building's StreetEasy page in the
     in-app browser: `WebExtractorKit` takes the rendered page, `LLMClientKit` extracts candidate rows,
     and one of us **confirms** them before they're saved. Nothing is saved without review.
2. **Every number shows its date and source** wherever it appears ("$5,450 · Oct 2026 · StreetEasy").
   Values older than six months are visually muted.
3. **A building's rent band** is the range of its last six months of observations. With fewer than two,
   show the single value and its date, not a range.
4. **Observations are append-only.** A correction is a new row, and the wrong one is deleted. This
   becomes the price history M2's listing tracking extends: a listing in M2 is observations with a
   lifecycle on top.

## The neighborhood file (settled 2026-11-16, from PR #15)

The Data Dashboard does break 2BR rents out by neighborhood, so layer 1 stays the 2BR median and the
all-units fallback isn't needed. The download is
`https://cdn-charts.streeteasy.com/rentals/TwoBd/medianAskingRent_TwoBd.zip`, a zip with one file,
`medianAskingRent_TwoBd.csv`. It's a wide table with one row per area and one column per month:

```
areaName,Borough,areaType,2010-01,2010-02,…,2026-10
West Village,Manhattan,neighborhood,…,7295.0
```

- The header is exactly `areaName,Borough,areaType`, then consecutive `YYYY-MM` columns. Any other
  column is an unknown header, and the import fails.
- `areaType` is `borough`, `city` or `neighborhood`. Only `neighborhood` rows are used, and an
  `areaType` outside those three fails the import.
- Rents look like `3800.0`. An empty cell means StreetEasy has no figure for that month: it's
  skipped, never stored as 0. Any other value that isn't a positive number fails the import.
- We keep the trailing 12 months, which is what the sparkline shows.
- The import starts from **our** neighborhoods and finds each one's StreetEasy area by name, through a
  small alias table in code, because StreetEasy's names aren't always ours (our Hell's Kitchen is its
  `Midtown West`). StreetEasy areas we don't track are ignored. Our neighborhoods with no match are
  named in the import's result, so we know which aliases to add.

## Consequences

- Building rents are only as fresh as our last visit to the page. That's acceptable for imagining,
  and M2 makes the numbers current once it matters.
- The importer is tied to StreetEasy's CSV column names. It must fail loudly on an unknown header,
  not import blanks (jon-platform `semantic-fidelity.md`).
