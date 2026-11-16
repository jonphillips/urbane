# Done Log — completed work

History, newest first. The PR that completes a dispatch adds its entry naming its branch
(jon-platform ADR-0005 D5). No dispatch reads this file.

## 2026-11-16 — Paced and retried Apple Maps place searches (`effort/import-search-pacing`)

- **Result:** Place searches now share a sequential rolling-window pacer, wait out MapKit throttles, and resolve imported neighborhoods and buildings before vignettes. Failed import rows can be retried from review while preserving the user’s review choices.
- **Verification:** The full check-drift gate passed: SwiftLint, 30 UrbaneCore and schema tests, dependency resolution, and the iOS build-for-testing pass.

## 2026-11-16 — M1 · S2 + S3 — Getting buildings in (`m1/s2-s3-buildings-in`)

- **Result:** The app opens on a full-screen map with neighborhood regions and status-colored building pins. Buildings are added by search, by a StreetEasy or building-site URL slug, or by a hand-placed pin, and each has Fix location. Import from chat decodes a pasted seed with or without fences, resolves every place on device, row by row, and shows one grouped review. Import then writes in one transaction, filling only empty fields; reviews replace by source and subject. Two migrations add `buildingReviews` and `buildings.mapItemIdentifier`; re-import matches by identifier, then by normalized street line.
- **Verification:** `scripts/check-drift.sh` passed: SwiftLint, 24 UrbaneLibrary tests, iOS build-for-testing, check-handoff. CI lint and test passed on `d9aa0d9`. The architect ran closeout by hand because the dispatch instructions kept the executor out of `NEXT_UP.md`.
- **Owed:** M1 S2's and S3's device gates, in [device-passes.md](device-passes.md).

## 2026-11-16 — M1 · S1 — Scaffold and the imagery proof (`m1/s1-imagery-proof`)

- **Result:** The Urbane scaffold, the M1 schema, and a debug screen that proves 3D snapshots and Look Around stills for the seed addresses.
- **Verification:** Jon answered ADR-0002's open questions from the iPad; the findings (hybrid 3D, adjustable Look Around, hand-placed pins) were folded into the plan by PR 4. This entry was added late, in the M1 · S2 + S3 closeout.
