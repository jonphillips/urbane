# ADR-0006: Import from chat — one paste carries a seed into Urbane, resolved and reviewed

*Status: proposed — 2026-11-16. Follows Galavant's trip-seed handoff (Galavant ADR-0048) and uses
`LLMHandoffKit`'s contract marker. Adds two columns (`buildings.summary` and
`buildings.mapItemIdentifier`, ADR-0005).*

## Context

Setting up Urbane means entering 15–20 buildings and 8–10 neighborhoods, each with a chapter (ADR-0004).
That's exactly what an open-ended chat is good at ("we like pre-war, light, near the L; what are we
missing in Williamsburg?"), and exactly what's tedious to retype. The volume is one burst plus a few
top-ups, so an MCP connection (jon-platform ADR-0007) costs more than it saves. Galavant already
proved the cheaper pattern: the chat returns one JSON object under a contract marker, and the app
reviews it in bulk.

Chats get things wrong. They give a building the wrong address, put a condo in a list of rentals, or
name a building that doesn't exist. The import has to catch that, not trust it.

## Decision

1. **The contract.** `docs/chat-contract.md` is the text pasted into a chat project's instructions
   (Claude or ChatGPT; the contract is plain text and works in either).
   The chat replies with prose as it likes, then a final message holding the marker line
   `URBANE-CONTRACT: v1` and one fenced JSON object of `neighborhoods` and `buildings` (each building
   may carry `reviews`, ADR-0007). Statuses use
   the four app values. A rejected building must carry a `rejectionReason`, so ruled-out buildings
   arrive already ruled out. **The contract forbids rent numbers**: rents come only from ADR-0003's
   named sources.
2. **The marker follows `HandoffContractMarker`'s rules**: a missing or older marker imports with a
   warning, and a newer one is refused. Decoding is strict: an unknown status or a missing required
   field fails that row loudly, and is never silently dropped or defaulted (jon-platform
   `semantic-fidelity.md`).
3. **Paste, from any device.** Import from chat is a sheet with one action: paste. No inbox file, no
   Mac helper, no MCP. A chat on the phone works.
4. **Every place is resolved on device before review.** Each building is looked up with `MKLocalSearch`
   (name + address, limited to the five boroughs). Neighborhood regions come from a search for
   "<name>, New York, NY". Vignette places are searched within their neighborhood's region.
   Coordinates from the chat are never used. Each row shows its match:
   - **One confident match:** checked by default, with the map item's name and address beside the
     chat's version, so a mismatch is visible.
   - **Several matches or none:** unchecked, flagged, with a picker or "skip". Nothing unresolved
     can be saved.
5. **One bulk review, nothing saved until Import.** It's grouped by neighborhood, with chapters
   collapsed and readable, and buildings marked as new, already in Urbane, or unresolved. Import writes
   everything in one transaction.
6. **Re-import is safe.** An existing building is matched by map item identifier
   (`buildings.mapItemIdentifier`, ADR-0005), then by normalized address. A building matched by
   address with no identifier gets the resolved one, since it's an empty field. An import fills
   **only empty fields**. It never overwrites a chapter, summary, status or anything we edited.
   Where a chapter already exists, the review offers "keep ours / replace" per neighborhood,
   defaulting to keep. A rejection never gets reversed by an import. The one exception
   is reviews, which replace by source and subject (ADR-0007): they're other people's words, not ours.
7. **What the chat's words become:** `chapter` → the neighborhood's chapter, a building's `summary` →
   `buildings.summary` (a short "why it's on the list", shown on the postcard), and `vignettes` →
   resolved neighborhood vignettes, and a building's `reviews` → `buildingReviews` rows (ADR-0007). The
   chat's prose outside the JSON isn't stored.

## Consequences

- Setup becomes one evening's conversation plus a review pass. Chapters still get edited in the
  app (ADR-0004: the words end up being ours).
- The contract is versioned. A v2 needs an app build first, because the marker check refuses newer
  versions.
- MCP stays a candidate in `open-questions.md`, worth building only if the chat needs to read Urbane,
  which would be recommendation behavior the brief rules out.
