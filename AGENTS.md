# Urbane

Private iPad-first app for Jon and Wendy to imagine, shortlist and finally choose a NYC rental
apartment. Two users, never the App Store, about a six-month life: export the data and shelve it when
the lease is signed.

Core idea: **buildings are persistent, listings are ephemeral.** Fall for buildings and neighborhoods
months ahead; watch for 2BR listings in the few that survive, about two months before moving in.

## Working mode — architect / executor

Claude = architect (docs, ADRs, milestones, effort briefs, reviews; **no feature code**). Codex =
executor (builds `docs/NEXT_UP.md`, one branch + PR per dispatch). The routing for a bare "go" and
"comments posted" is in jon-platform `AGENTS.md`. The full loop is in
`jon-platform/docs/agent-collaboration.md` and ADR-0005. Jon approves plans by merging plan PRs and
decides escalations.

## Read first

- `~/code/jon-platform`: the cross-app house rules (style, persistence and sync laws, toolchain, agent
  workflow). Urbane docs hold only the **apartment-search domain**.
- `docs/README.md` indexes everything below.
- `docs/PRODUCT.md`: what we're building and what we deliberately aren't.
- `docs/decisions/`: settled choices. Check them before proposing architecture, and don't
  re-litigate them.
- `docs/NEXT_UP.md`: the one dispatch. Executor: it's your only planning input; if it's empty, stop
  and ask. Verification is in `docs/verification.md`. The architect also reads `docs/open-questions.md`;
  the executor never does.

## Stack

The house stack (jon-platform `AGENTS.md`, `docs/ios/`), bound here by ADR-0001. Urbane's own parts:

- SwiftUI multiplatform, iPad first. iPhone has to work; Mac runs as "Designed for iPad".
- MapKit only: maps, Look Around, transit ETAs, places. No Google APIs and no API keys (ADR-0002).
- Reuses `WebExtractorKit` (browser capture), `LLMClientKit` (field extraction), `LLMHandoffKit` (the
  chat contract marker, ADR-0006) and `CloudSyncKit`
  (sync health, backup) from jon-platform by path. Urbane creates **no new shared packages**.
- Plain product name everywhere: `Urbane`, `com.jonphillips.urbane`, `iCloud.com.jonphillips.urbane`.
- Reusable, MapKit-free logic goes in the local SPM package (`UrbaneLibrary`), with tests.

## Restraint

Urbane is short-lived. Before adding a table, a screen or a setting, ask whether it will still matter
in month five. If it's a nice-to-have, it goes in `open-questions.md`, not a milestone.
