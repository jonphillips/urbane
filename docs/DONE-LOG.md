# Done Log — completed work

History, newest first. The PR that completes a dispatch adds its entry naming its branch
(jon-platform ADR-0005 D5). No dispatch reads this file.

## 2026-11-17 — M1 · S7 — The subway on the map (`m1/s7-subway-map`)

- **Result:** Bundled a dated MTA station snapshot, drew route markers on both maps, and added the nearest stations to building sheets.
- **Verification:** scripts/check-drift.sh passed: SwiftLint (0 violations), 61 UrbaneLibrary tests, and iOS build-for-testing.
- **Owed:** M1 S7's device gate, in [device-passes.md](device-passes.md).

## 2026-11-17 — Rent numbers, commutes, and StreetEasy capture (`m1/s6-rent-numbers`)

- **Result:** Added StreetEasy's two-bedroom rent import and 12-month sparkline; reduced listing pages for on-device extraction with confirmation, dated rent bands, and stored transit commutes on a paced MapKit budget with background fill. Added validated building link editing.
- **Verification:** SwiftLint, all 59 UrbaneLibrary tests, and iOS build-for-testing passed.
- **Owed:** M1 S6's device gate, in [device-passes.md](device-passes.md).

## 2026-11-16 — M1 · S4 + S5 device pass

- **Result:** Passed on Jon's iPad, under the gate as amended by #13 (Look Around views aren't adjustable). The Ashland's default facade still faced its front door ("250"), and the full-screen 3D map and Look Around viewer both work. Jon merged #12 after the pass.
- **Verification:** Found during the pass and fixed in #12: the pager reset because the gallery sat inside a `List` row, the gallery and sheet were too small, and the editor's pin-dropping didn't give useful views (dropped, ADR-0002 § Resolved by S4). The full-screen 3D map's crash was Metal API Validation, a debug-only check, catching Apple's VectorKit renderer; it's off in the scheme (`20dfa84`) and doesn't apply outside Xcode runs.

## 2026-11-16 — M1 S4 + S5 — Building postcard and neighborhood chapters (`m1/s4-building-postcard`)

- **Result:** Added a swipeable building postcard and editable neighborhood chapters, region fixes, plus field-specific import decoding errors.
- **Verification:** scripts/check-drift.sh passed: SwiftLint, 33 Urbane tests, and the iOS build-for-testing gate.
- **Owed:** M1 S4 + S5's device gate, in [device-passes.md](device-passes.md).

## 2026-11-16 — M1 · S2 and S3 device passes

- **Result:** Both gates passed on Jon's iPad. **S2:** 420 Kent Avenue was added to the map. **S3:** a full seed (11 neighborhoods, 20 buildings, about 50 vignettes) resolved and imported with no throttle errors after the search-pacing effort. A second paste added one Openigloo review to The Ashland.
- **Verification:** The review was synthetic, so this confirms the review import path, not a real Openigloo read. It can't be seen in the app until S4's "What renters say", and S4's gate confirms it. A real Openigloo review comes with Jon's next research session. Found during the pass and folded into S5 and the next dispatch: oversized neighborhood regions, Fulton / Seaport resolving to Brooklyn, doubled map labels, and decode errors that don't name their field.

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
