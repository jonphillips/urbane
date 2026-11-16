# ADR-0004: The words are ours — chapters and "A Tuesday here" are authored, not generated

*Status: proposed — 2026-11-16*

## Context

The neighborhood commentary and the "A Tuesday here" sketches are what turn Urbane from a tracker into a
way of imagining a life. Generated text per building would be bland and identical everywhere, and it's a
gold-plating trap. The house stance (jon-platform Seam Ledger, "Verbatim taste notes…") is that the app
stores what people wrote and the chat does the synthesizing.

## Decision

1. **Neighborhood chapter**: one synced text field per neighborhood, 150–250 words, plus an ordered set
   of 3–5 vignettes (ADR-0002). We draft it with Claude in a chat, edit it, and paste it into the app.
   Stored exactly as written.
2. **"A Tuesday here"**: optional, per building, **for at most five buildings**. It's an ordered list of
   stops (morning, commute, evening, walk), each a short line of text and a vignette. The commute stop
   shows the stored transit time. A building without one shows nothing, not an empty state asking
   for one.
3. **No in-app generation in M1.** No "write this for me" button. If drafting in a chat gets tedious,
   adding MCP access (jon-platform ADR-0007, stage-only writes) is a candidate, not a plan.
4. **Reactions are per person, word for word**: one row per (building, person) with a rating, a
   favorite flag and a free-text note (ADR-0005).

## Consequences

- Writing ten chapters is an evening's work. That's acceptable, and it's also part of the fun.
- The app can't make a building sound appealing by itself. That's the point.
