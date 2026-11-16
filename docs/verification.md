# Verification

The standing pattern for every dispatch (jon-platform ADR-0005). Compile and test, then hand off:
Jon reviews on his own device, so **no simulator walkthroughs, installs, screenshots or taps**. Name any
device-only risk in the PR as unverified, and stop.

## The gate

`scripts/check-drift.sh` is the single entry point, modeled on Galavant's: SwiftLint,
`swift test --package-path UrbaneLibrary`, a `build-for-testing` pass for the app target, and the shared
`check-handoff` (warn-only). Noisy stages run through jon-platform's `quiet-run`. M1 · S1 creates the
script; until it exists, the S1 PR states which of these it ran.

## What can't be tested here

Look Around coverage, scene direction, 3D snapshot quality, `MKDirections` transit ETAs, and CloudKit
sharing are verified only on a device. Pure logic (URL slug parsing, rent bands, CSV import, dedup
survivor order, extraction against saved page fixtures) lives in `UrbaneLibrary` and is unit-tested.
