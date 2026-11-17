# Turning on sync and sharing, through Production (M1 · S8b)

The order for moving Urbane from local-only storage to a CloudKit library shared with Wendy. Each step
says who does it. The general rules are in jon-platform `docs/ios/persistence-and-sync.md` (§ Rollout &
enablement, § Adding a synced table or column, § Creating and accepting the share) and `testflight.md`.
This file only adds what is particular to Urbane.

## What's different about Urbane

- **The library has never synced.** Jon's iPad holds the real library (chat-seeded neighborhoods and
  buildings, rents, vignettes, hero images, reviews, commutes), all local. Nothing exists in either
  CloudKit environment. So the first upload goes into an **empty Production zone**. That's the case
  where unpatched SQLiteData loses rows (jon-platform `SEAM-LEDGER.md`, "Patched SQLiteData"), so S8b
  ships with Yes Chef's vendored, patched copy.
- **Jon's library must never sync from a Development build.** Xcode builds talk to Development and
  TestFlight builds talk to Production. SQLiteData's sync metadata is keyed by the container, not the
  environment. If Jon's real library ever uploads to Development, a later TestFlight build will believe
  it already uploaded, and Production stays partly empty, as happened to Yes Chef. **Exercise
  Development only on the Simulator, or on a device without the real library, and keep sync's opt-in
  off on Jon's iPad until step 9.**
- **Urbane isn't on TestFlight yet.** Wendy can only get it through TestFlight, and TestFlight builds use
  Production. So Production is a prerequisite of the device gate, not an afterthought.

## Steps

### Before S8b's code (Jon, one-time, in Apple's consoles)

1. **Container and capabilities.** In Certificates, Identifiers & Profiles, create the iCloud container
   `iCloud.com.jonphillips.urbane`, and enable iCloud (CloudKit, with that container) and Push
   Notifications on the App ID `com.jonphillips.urbane`.
2. **App Store Connect.** Create the Urbane app record for `com.jonphillips.urbane`, and add Wendy as an
   internal tester. She's already on the team for Galavant. The shared `asc` API key covers it
   (jon-platform `testflight.md` § One-time setup).

### S8b's PR (executor, behind the opt-in)

3. The code in the S8b brief: entitlements, `CKSharingSupported`, the remote-notification background mode,
   the patched SQLiteData override, `CloudSyncKit` with `startImmediately: false` behind a persisted opt-in
   (default **off**), sync health, backup/restore, share create and accept, the iCloud identity binding,
   and `testflight.conf` (mirror Galavant's: `SCHEMA_GATE=1`, `EXPECTED_SCHEMA_FIELDS`).
4. **Schema with `cktool`, into Development.** Every synced table is new to CloudKit, so the file adds
   all of them: `searches`, `people`, `neighborhoods`, `neighborhoodRents`, `buildings`,
   `neighborhoodVignettes`, `buildingVignettes`, `buildingReviews`, `commutes`, `rentObservations`,
   `reactions` and `photos`. Follow § Adding a synced table or column steps 1–3 and 5–6. **Step 4 there
   is Jon's:** the PR shows the diff against the fresh (empty) export, and Jon OKs it before the import.
   Write `EXPECTED_SCHEMA_FIELDS` from the same file.
5. Exercise sync and sharing in Development on the Simulator, as far as one account allows: the engine
   starts, rows upload, and the share sheet opens. Acceptance needs two Apple IDs, so it waits for step 11.

### The cutover (Jon, after S8b merges)

6. **Deploy Development → Production** in the CloudKit Console. This is one-way: after this, fields can't
   be removed.
7. **First TestFlight build.** `testflight` with the schema gate. The build installs over Jon's current
   app on his iPad and keeps the library, with sync still off.
8. **Back up before syncing.** In Urbane's Settings, take a backup to Files and note each table's row count,
   which the backup reports. This is the copy to restore from if anything goes wrong.
9. **Turn sync on, on Jon's iPad only.** Keep Urbane in the foreground until sync health reads up to date.
   The library is small (hundreds of rows, not Yes Chef's 50,000), so expect minutes.
10. **Share.** Settings → Share with Wendy (owner only). Send her the invitation.
11. **Wendy installs fresh from TestFlight and accepts.** Her first launch creates a throwaway local root;
    accepting the share replaces it (S8b brief, "One root per device"). Let her iPad download until
    sync health reads up to date, then check Settings shows one Jon and one Wendy.
12. **Verify with counts, never with the status.** Take a backup on each iPad and compare row counts table
    by table. If a table differs, match rows by ID (persistence-and-sync § Moving a populated library to
    Production). Then run the held sharing pass in `device-passes.md`: each of us reacts to a building,
    and the other sees it within a minute.

## If it goes wrong

- **Rows missing from Production after step 9.** Don't delete anything. Re-saving a missing row uploads
  it (CloudKit answers `unknownItem`, and the engine saves the row as new). For many rows, restore from
  step 8's backup on Jon's iPad. A restore re-seeds as an authoritative peer.
- **Wendy's iPad stalls.** Compare counts before acting. A first download parks children whose parents
  haven't arrived yet; the patched SQLiteData retries them without re-downloading every batch.
- **A save is rejected after a schema change.** A field is missing from Production. Add it through
  § Adding a synced table or column, and Jon deploys again.
