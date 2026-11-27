# Urbane

Private iPad-first app for Jon and Wendy to imagine, shortlist and finally choose a NYC rental
apartment. Two users, never the App Store, about a six-month life: export the data and shelve it when
the lease is signed. [`docs/PRODUCT.md`](docs/PRODUCT.md) has what we're building and what we
deliberately aren't.

Core idea: **buildings are persistent, listings are ephemeral.** Fall for buildings and neighborhoods
months ahead; watch for 2BR listings in the few that survive, about two months before moving in.

## Working mode

Architect / executor, per jon-platform `AGENTS.md`.

## Read first

1. `~/code/jon-platform/AGENTS.md`: the house stack and rules. Urbane's docs hold only the
   **apartment-search domain**.
2. [`docs/README.md`](docs/README.md): the map of this repo's docs.

## What's Urbane's own

- **iPad first** (ADR-0001). iPhone has to work; Mac runs as "Designed for iPad".
- **MapKit only:** maps, Look Around, transit ETAs, places. No Google APIs and no API keys (ADR-0002).
- **Reuses, never adds, shared packages.** `WebExtractorKit` (browser capture), `LLMClientKit` (field
  extraction), `LLMHandoffKit` (the chat contract marker, ADR-0006) and `CloudSyncKit` (sync health,
  backup) come from jon-platform by path. Urbane creates **no new shared packages**.
- **Plain product name everywhere:** `Urbane`, `com.jonphillips.urbane`, `iCloud.com.jonphillips.urbane`.
- Reusable, MapKit-free logic goes in `UrbaneLibrary`.

## Restraint

Urbane is short-lived. Before adding a table, a screen or a setting, ask whether it will still matter
in month five. If it's a nice-to-have, it goes in `open-questions.md`, not a milestone.
