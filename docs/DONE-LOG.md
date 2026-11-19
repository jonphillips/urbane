# Done Log — completed work

History, newest first. The PR that completes a dispatch adds its entry naming its branch
(jon-platform ADR-0005 D5). No dispatch reads this file.

## 2026-11-19 — M1 · S7g — A wider panel and building links under the photo (`codex/m1-s7g-building-links`)

- **Result:** Widened the map-side building panel to 420–840 pt based on the home map width, preserving at least 360 pt of visible map. Added Website and StreetEasy buttons under the gallery in both layouts; missing links open Edit links, and the website action was removed from the ellipsis menu.
- **Verification:** scripts/check-drift.sh passed: SwiftLint (0 violations), all 77 UrbaneLibrary tests, dependency resolution, and iOS build-for-testing. check-handoff --strict passed.
- **Owed:** M1 S7g's device gate, in [device-passes.md](device-passes.md).

## 2026-11-18 — Building detail beside the map, links in Safari (`m1/s7f-building-detail-panel`)

- **Result:** Regular width now shows building details in a swappable map-side panel; compact width retains the detail sheet. Read-only links open externally, while capture browsers use page sizing.
- **Verification:** SwiftLint strict passed with zero violations; all 69 UrbaneLibrary tests passed; iOS Simulator build-for-testing succeeded.
- **Owed:** M1 S7f's device gate, in [device-passes.md](device-passes.md).

## 2026-11-18 — M1 · S7e — Satellite 3D on the home map (`m1/s7e-satellite-3d`)

- **Result:** Added the Satellite 3D home-map toggle, realistic hybrid style, camera tilt, and map pitch and compass controls.
- **Verification:** scripts/check-drift.sh passed: SwiftLint, 69 UrbaneLibrary tests, dependency resolution, and iOS simulator test build.
- **Owed:** M1 S7e's device gate, in [device-passes.md](device-passes.md).

## 2026-11-18 — Rotate JON_PLATFORM_PAT from one command (`effort/platform-pat`)

- **Result:** Added PAT rotation tooling in jon-platform PR #146 and actionable CI diagnostics in ci-workflows PR #2; Urbane PR #41 records the shared changes.
- **Verification:** All jon-platform script tests, check-index, the dry-run consumer list and live PAT check passed. actionlint and four local Bash 3.2 cases for ci-workflows passed.

## 2026-11-18 — Shared patched SQLiteData vendor (`effort/shared-sqlitedata-vendor`)

- **Result:** Moved the patched SQLiteData vendor to jon-platform and updated the Yes Chef (#532) and Urbane (#39) consumers; the shared package landed in jon-platform PR #144.
- **Verification:** scripts/check-drift.sh passed (77 library tests, SwiftLint, and the app test-target build); workspace package resolution passed for Urbane and YesChef.

## 2026-11-18 — M1 · S8b — Sync and sharing on, through Production (`codex/m1-s8b-sync-sharing`)

- **Result:** Urbane syncs through CloudKit behind a persisted opt-in (default off) and an iCloud account check, using the patched SQLiteData 1.13.0 vendored from Yes Chef. Settings has sync health with a row count for all 12 synced tables, backup and restore, an owner-only Share with Wendy, and share acceptance in both scene paths. Root ownership comes from the CloudKit zone owner: a participant never seeds people, an empty local root is removed on accept, and a populated one is kept without merging, with a dismissable notice. "This is me" claims a person for the iCloud account only while sync is on, one person per account. The full schema is imported to Development, and testflight.conf carries the schema gate.
- **Verification:** scripts/check-drift.sh passed: SwiftLint, 77 library tests, package resolution, and the iOS build-for-testing. The architect exported both environments on 2026-11-18: Development matches all 186 expected fields and their types; Production is still only Users.

## 2026-11-17 — M1 · S7d — Read StreetEasy unit cards without the model (`m1/s7d-streeteasy-unit-cards`)

- **Result:** Added bounded StreetEasy unit-card parsing before model fallback, with deduplication and bedroom detection from the reduced page text.
- **Verification:** scripts/check-drift.sh passed: SwiftLint (0 violations), 69 UrbaneLibrary tests, dependency resolution, iOS build-for-testing, and check-handoff.
- **Owed:** M1 S7d's device gate, in [device-passes.md](device-passes.md).

## 2026-11-17 — M1 · S7c and S8a device pass

- **Result:** Passed on Jon's iPad. Commute rows open transit directions in Maps, and Jon and Wendy
  each left a reaction on one device and saw both. Capture on 420 Kent still needs the **2 beds** tab
  selected (expected), and on that tab it offers #802 and #560 but never #1009, the first card. The
  page and the model both read all three on the Mac, so S7d reads the unit cards in code.

## 2026-11-17 — Two opinions, on one device (`m1/s8a-opinions`)

- **Result:** Seeded Jon and Wendy, added device-local identity, per-person building reactions, reasoned rejection status, and a rejected-building map filter.
- **Verification:** scripts/check-drift.sh: SwiftLint clean, 68 UrbaneLibrary tests passed, and iOS build-for-testing passed.
- **Owed:** M1 S8a's device gate, in [device-passes.md](device-passes.md).

## 2026-11-17 — M1 S7c — Rent tab guidance and transit directions (`m1/s7c-transit-directions`)

- **Result:** Added 2 beds tab guidance when rental capture finds units but no two bedroom candidates, and made commute rows open transit directions in Maps.
- **Verification:** scripts/check-drift.sh passed: SwiftLint, 63 UrbaneLibrary tests, package resolution, and iOS build-for-testing.
- **Owed:** M1 S7c's device gate, in [device-passes.md](device-passes.md).

## 2026-11-17 — M1 · S6, S7 and S7b device pass

- **Result:** Passed on Jon's iPad ("overall things look good"). Covered: the S6 checks (transit
  times, the StreetEasy 2BR CSV import, Edit links, and the building sheet staying open through rent
  capture, #19), S7's subway markers and nearest stations, and S7b's rent capture and marker scaling.
  Rent capture on 420 Kent works once the page's **2 beds** tab is selected. With the default Studio
  tab, it sees only the five studios. S7c makes the message say so, and adds transit directions from
  commute rows. Jon merged #22 after the pass.

## 2026-11-17 — M1 S7b — Fixes from the S6 and S7 device pass (`m1/s7b-rent-and-subway-fixes`)

- **Result:** Rent capture now uses guided structured output, filters and normalizes two bedroom units, reports what the model found, and exposes reduced page text for copying when no candidates match. Subway station markers now scale with camera distance and remain visible through 10 km.
- **Verification:** SwiftLint passed; 62 UrbaneLibrary tests passed; Xcode build-for-testing succeeded; check-handoff --strict passed.
- **Owed:** M1 S7b's device gate, in [device-passes.md](device-passes.md).

## 2026-11-17 — M1 · S7 — The subway on the map (`m1/s7-subway-map`)

- **Result:** Bundled a dated MTA station snapshot, drew route markers on both maps, and added the nearest stations to building sheets.
- **Verification:** scripts/check-drift.sh passed: SwiftLint (0 violations), 61 UrbaneLibrary tests, and iOS build-for-testing.
- **Owed:** M1 S7's device gate, in [device-passes.md](device-passes.md).
## 2026-11-17 — M1 S6 follow-up — Keep rent capture sheet open (`m1/s6-rent-capture-presentation`)

- **Result:** Moved the StreetEasy browser and rent review presentations to `BuildingDetailSheet` so the rent section stays attached to a stable presenter.
- **Verification:** SwiftLint, all 59 UrbaneLibrary tests, and iOS build-for-testing passed. Browser-to-review presentation remains unverified on iPad.

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
