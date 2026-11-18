# Effort — One patched SQLiteData, kept in jon-platform

Status: Dispatched
Summary: Yes Chef and Urbane each carry a patched copy of SQLiteData in their own `Vendor/sqlite-data`. With both apps in `jon-platform-workspace`, Xcode finds two top-level packages named `sqlite-data` and resolves nothing, so no scheme in the workspace builds. Move the one copy into jon-platform and point both apps at it.

Related: [M1 · S8b](../milestones/M1-browse.md#s8b--sync-and-sharing-on-through-production) ·
jon-platform `SEAM-LEDGER.md` ("Patched SQLiteData") · [Efforts index](README.md)

Three PRs, in this order: jon-platform first, then Yes Chef and Urbane. App CI clones jon-platform `main`,
so the app PRs open after the jon-platform PR merges (jon-platform `agent-collaboration.md` § Dispatches
whose code lands in jon-platform). Branch `effort/shared-sqlitedata-vendor` in each repo, from a fresh `main`.
No schema change, no sync behavior change, and no SQLiteData source change.

## Why

S8b (urbane #32) vendored a byte-for-byte copy of Yes Chef's patched SQLiteData 1.13.0, as the brief asked.
Each app's copy is fine on its own. On 2026-11-18, Jon's build of Urbane from `~/code/jon-platform-workspace`
failed with "Missing package product 'UrbaneSchema'". The cause, from
`xcodebuild -workspace jon-platform-workspace.xcworkspace -scheme Urbane -resolvePackageDependencies`, is:

```
xcodebuild: error: Could not resolve package dependencies:
  found multiple top-level packages named 'sqlite-data'
```

A workspace resolves packages once for every project in it, so Yes Chef, Galavant and the rest fail to resolve
too. Two references to the **same** path are one package, so a single shared copy fixes it. That is the move
the seam ledger already names.

## Changes

1. **jon-platform: add `Vendor/sqlite-data`.** Copy it from Yes Chef's `Vendor/sqlite-data` at `main`,
   without `.build/` or `.swiftpm/`. Yes Chef's copy is the source: Urbane's differs from it only by
   whitespace. Rename `YESCHEF-PATCH.md` to `PATCH.md`, and change only its opening line and the parts that
   say whose copy it is: one shared copy, consumed by Yes Chef and Urbane. Keep every patch note, test and
   the exit condition as written. Change nothing under `Sources/` or `Tests/`. Don't change
   `packages/CloudSyncKit/Package.swift`: it keeps its GitHub dependency, and each app overrides it as today.
2. **Yes Chef:** point `project.yml`'s `SQLiteData` package at `../../jon-platform/Vendor/sqlite-data`,
   delete `Vendor/sqlite-data`, regenerate, and commit the updated `Package.resolved`. Update the two
   references in `docs/verification.md` and any in scripts or lint excludes. Leave decisions, `DONE-LOG.md`
   and archived briefs as they are: they're history.
3. **Urbane:** point `project.yml`'s `SQLiteData` package at `../jon-platform/Vendor/sqlite-data`, and
   `UrbaneLibrary/Package.swift` at `../../jon-platform/Vendor/sqlite-data`. Delete `Vendor/sqlite-data`,
   regenerate, and commit both `Package.resolved` files.

## Done when

- **jon-platform PR:** `diff -r` against Yes Chef's copy shows only the renamed notes file.
  `scripts/quiet-run swift test --package-path Vendor/sqlite-data` passes, including
  `ReferenceViolationTests.addReminderAfterListSaveWasRejected`. The PR body lists both runs, and the title
  names this effort.
- **Each app PR:** its own `scripts/check-drift.sh` passes, and its CI is green.
- **The workspace resolves.** With both app branches checked out locally, run
  `xcodebuild -workspace ~/code/jon-platform-workspace.xcworkspace -scheme Urbane -resolvePackageDependencies`,
  and the same with `-scheme YesChef`. Both succeed. Paste the last lines of each into the Urbane PR.
- **Records:** Urbane's PR runs closeout (ADR-0005 D16) and names all three PRs in its DONE-LOG entry.
  Yes Chef's PR adds its own DONE-LOG entry that names this effort, and doesn't touch Yes Chef's
  `NEXT_UP.md`.

**Escalated to Jon:** shared code in jon-platform. Neither app's synced schema or sync code changes, and
there's no device gate: the engine source is byte-identical.

**After the merges (architect):** Yes Chef's `device-passes.md` gate line links
`../Vendor/sqlite-data/YESCHEF-PATCH.md`, and its open question on replacing the vendored copy names the
path. Repoint both in a Yes Chef plan PR, and mark the seam-ledger row lifted in jon-platform.

## Not in this effort

- Pointing `CloudSyncKit` itself at the shared copy. That would move Galavant from SQLiteData 1.6.6 to the
  patched 1.13.0, which the seam ledger notes but doesn't schedule.
- SwiftPM's "conflicting identity" **warning** in Urbane's `swift test` (the vendored path against
  CloudSyncKit's GitHub URL). It stays a warning, and the ledger tracks it.
