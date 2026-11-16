# ADR-0005: The shareable graph

*Status: proposed — 2026-11-16. Governed by jon-platform `persistence-and-sync.md` (single-FK rule, no
unique indexes, UUID keys, one row per item and person). Escalate any change to Jon (schema, sync).*

## Decision

One shared root, `Search`, and a tree where every table has **one real foreign key** to its parent.
Any second relationship is a **loose UUID** column.

| Table | Rides the share through (FK) | Loose UUIDs | Notes |
|---|---|---|---|
| `searches` | — (root) | | one row; title; move-in target date (nullable) |
| `people` | `searchID` | | `displayName`; `iCloudUserRecordName` nullable (Galavant ADR-0051 shape) |
| `neighborhoods` | `searchID` | | name, `chapter` text, region center and span, sort order |
| `neighborhoodRents` | `neighborhoodID` | | month, median 2BR rent, source label |
| `buildings` | `neighborhoodID` | | name, address, coordinate, `summary` text (ADR-0006), `status` enum, `rejectionReason`, StreetEasy URL, building site URL, `heroImage` BLOB |
| `neighborhoodVignettes` | `neighborhoodID` | | place name, coordinate, map item id, caption, order |
| `buildingVignettes` | `buildingID` | | same columns; facade, corner, and "A Tuesday here" stops (`tuesdayPart` enum, nullable) |
| `commutes` | `buildingID` | | `destination` enum, transit seconds, computed date |
| `rentObservations` | `buildingID` | | rent, unit, square feet, date seen, source URL |
| `reactions` | `buildingID` | `personID` | rating 1–5, favorite, note. One row per (building, person) |
| `photos` | `buildingID` | `personID` | BLOB, caption, date taken. (Visits are M3; photos are cheap now) |

- **Vignettes are two tables, not one with two parents.** A neighborhood vignette and a building
  vignette never move between parents, so separate tables keep the single-FK rule without loose links.
- **`status`** is a persisted `Int` enum: `exploring`, `watching`, `tourCandidate`, `rejected`.
  `rejectionReason` is non-empty only when the status is `rejected`. Enforce this in the write path,
  since a CHECK constraint isn't worth a fight with sync.
- **`destination`** is an enum of five: SoHo, Tribeca, West Village, Lower East Side, Midtown, each with a
  fixed representative coordinate in code.
- **Logical uniqueness** (one reaction per building and person, one commute per building and
  destination, one rent row per neighborhood and month) uses the house's upsert plus dedup-on-read,
  with a stable survivor order.
- **Local-only, never synced:** the rendered snapshot cache (ADR-0002) and "this device is me"
  (`@Shared(.appStorage)`).
- **Spell-check every table and column before the first Production deploy.** Synced names are forever.

## M2 preview (not built in M1)

`listings` (FK `buildingID`) with a lifecycle enum, and `rentObservations` gains a loose `listingID`.
That's an additive change and fits the tree.
