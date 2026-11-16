# ADR-0001: A native app on the house stack, not a web app

*Status: proposed — 2026-11-16*

## Context

The first brief ("NYC Homebase", drafted in ChatGPT) proposed Next.js, Supabase and Vercel, with
Google Maps, the Street View embed, and a Gmail parser for StreetEasy alerts. The arguments for web
were desktop and iPad use, link sharing, and the email parser needing a server anyway.

None of those hold here:

- Two people on iPads and Macs. A SwiftUI app runs on both ("Designed for iPad" on Mac).
- Sharing between the two of us is a CloudKit share, which Galavant already runs on Production
  (jon-platform `persistence-and-sync.md` § Creating and accepting the share).
- Email ingestion doesn't need a server we host (ADR-0003, and `open-questions.md` § Watch).
- MapKit covers the maps, Look Around, transit ETAs and points of interest, for free and without
  keys (ADR-0002).
- Jon deploys native apps routinely (`scripts/testflight`). Deploying a web app is the unfamiliar path.

## Decision

1. Urbane is a **SwiftUI multiplatform app on the house stack**: SQLiteData + CloudKit, no server,
   no auth, Point-Free without TCA. jon-platform `AGENTS.md` applies in full.
2. It's **shared from day one in the schema, and syncs last.** The whole graph descends from one
   shared root (ADR-0005). Sync is gated and turned on in the last M1 slice, as jon-platform
   § Rollout says.
3. It's **its own app, not a Galavant feature.** Galavant's pool of ideas is long-lived and sorted
   by region. Urbane is built around buildings and dated rents, and is retired in six months. Mixing
   them would leave Galavant carrying apartment tables forever.
4. **It reuses, and doesn't extract.** WebExtractorKit, LLMClientKit and CloudSyncKit are consumed by
   path. The share flow follows Galavant's code. Urbane is the trigger for the Seam Ledger row "Two-
   person share root…", which gets resolved by comparing the two then, not by building a package now.

## Consequences

- No web access: you can't send someone a link to a building. That's acceptable, because the only
  other user is Wendy, and she has the app.
- TestFlight builds expire after 90 days, so Urbane needs about two releases over its life.
- Requires the paid Apple Developer membership, which is already in place.
