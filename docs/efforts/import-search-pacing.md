# Effort — A full chat seed resolves without Apple Maps throttling it

Status: Dispatched
Summary: Jon's first real seed needs about 80 place searches, and Apple Maps allows 50 a minute, so many rows came back with `MKError.loadingThrottled` (error 3). Pace every place search under Apple's limit, wait out a throttle instead of retrying in half a second, resolve the rows that matter most first, and let the review retry what failed.

Related: [M1 · S3](../milestones/M1-browse.md#s3--import-from-chat) · [ADR-0006](../decisions/0006-import-from-chat.md) ·
[Efforts index](README.md)

Branch `effort/import-search-pacing`, from a fresh `main`. One PR. No schema change, no sync change,
and no contract change.

## Why

On 2026-11-16 Jon pasted a seed of 11 neighborhoods, about 50 vignettes and 20 buildings into Import
from chat, roughly 80 `MKLocalSearch` calls back to back. A "significant number" of rows came back with
`MKErrorDomain` error 3, `MKError.loadingThrottled`.

Apple's guidance is **at most 50 requests per 60 seconds** per app. Over that, the server refuses
requests until the window resets. The underlying `GEOErrorDomain` -3 error carries `maxRequests`,
`windowSize` and `timeUntilReset`, but Apple says not to rely on those details
([forum thread](https://developer.apple.com/forums/thread/760867)). PR 5's retry
(`PlaceSearchClient.liveValue`) waits 250 ms and then 500 ms, which is nowhere near a 60-second window.
So once the budget is spent, every later row fails.

## Changes

1. **Pace every place search.** In `UrbaneCore`, wrap the place search in a pacer shared by the whole
   app (manual add, Fix location and import all draw on one budget): at most **45 searches in any
   rolling 60 seconds**, sequential, time read from an injected clock (`\.continuousClock`) so tests
   can drive it. A search waits for a free slot; it never fails for lack of one.
2. **Wait out a throttle.** On `loadingThrottled`, wait 60 seconds and then retry that query, up to
   **3 waits** per query. After the third, the row is unresolved with the error text, as PR 5 does
   for other failures. Don't parse `timeUntilReset`. Remove the 250/500 ms retry.
3. **Resolve the important rows first.** In `prepareReview`, search neighborhoods, then buildings,
   then vignettes. If Jon gives up partway, the rows that matter have resolved.
4. **Say why it's slow.** The progress line keeps "Resolving 23 of 81…" and adds "Waiting for Apple
   Maps (about 40 s)" while the pacer or a throttle is holding a search. Cancel stops the resolve
   promptly, even mid-wait.
5. **Retry from the review.** When any row failed (an error, not "no match"), the review shows
   **Retry failed rows**. It re-searches only those rows through the same pacer, keeping every pick,
   skip and replace toggle Jon has already set.

## Decisions

- **45, not 50.** This leaves headroom for searches the pacer can't see, such as one already in flight
  when a sheet opens. A full 80-place seed takes about two minutes, which is fine for a once-an-evening
  import.
- **Sequential, no parallel searches, no cache across pastes.** Re-import is rare and the budget is the
  limit either way.
- **A fixed 60-second wait** rather than the error's `timeUntilReset`, per Apple's advice not to rely on
  it.

## Done when

- **UrbaneCore tests** (test clock, fake underlying search):
  - 100 queries through the pacer: no more than 45 start in any 60 seconds of test-clock time, and all
    100 complete;
  - a query throttled once waits 60 seconds of test-clock time, then succeeds;
  - a query throttled four times returns unresolved with the error text, after three waits;
  - `placemarkNotFound` still returns no matches without waiting;
  - cancelling during a wait ends the search promptly with `CancellationError`.
- The order of searches in `prepareReview` is neighborhoods, buildings, vignettes. Test it if the search
  list is pulled into `UrbaneCore`; otherwise name it in the PR.
- The full set in `docs/verification.md` passes.
- Closeout records no new gate. The owed **M1 S3** gate in `device-passes.md` is the device check:
  Jon's full seed resolves with no throttling errors.

**What tests can't show:** Apple's real throttle. Name it in the PR as unverified.

## Out of scope

- Changing the chat contract to send fewer vignettes.
- Caching search results, or resolving vignettes lazily after import (ADR-0006 resolves every place
  before review).
