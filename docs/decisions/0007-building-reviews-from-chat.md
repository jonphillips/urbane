# ADR-0007: What renters say — building reviews come in through the chat, dated and sourced

*Status: proposed — 2026-11-16. Extends ADR-0005 (one table) and ADR-0006 (one optional array in the
contract). Escalate any change to Jon (schema, sync).*

## Context

When we're choosing between tour candidates, the deciding question is often how a building and its
landlord treat tenants: heat in winter, repairs, management that answers. Openigloo collects exactly
that for NYC rentals, and there are other ratings too (Google, Reddit threads). None of them has an API
we'd want. ADR-0002 rules out Google APIs, and the docs treat scraping as out of scope (ADR-0003).

But the chat can already do the research. In a normal conversation, ChatGPT with web search has pulled
Openigloo comments and ratings for buildings we discussed. Import from chat (ADR-0006) already carries a
chat's research into Urbane as one checked, reviewed paste. Reviews are one more section of that paste.

Folding reviews into `buildings.summary` would lose what makes a rating honest. ADR-0003's rule
applies here too: every number shows its date and source. A building can have several sources, and
each needs its own date and link.

## Decision

1. **A `buildingReviews` table** (FK `buildingID`), one row per (building, source, subject):

   | Column | Type | Notes |
   |---|---|---|
   | `source` | text | "Openigloo", "Google", "Reddit": the site, as the chat names it |
   | `subject` | `Int` enum | `building` or `landlord` (`about` in the JSON). Openigloo rates the two separately |
   | `sourceURL` | text | Required: the page the chat read |
   | `rating`, `ratingScale` | real, nullable | Both present or both null; 3.8 of 5. Reddit has no score |
   | `reviewCount` | integer, nullable | |
   | `newestReviewMonth` | text, nullable | `YYYY-MM` of the newest review, so a 4.5 from 2019 reads as old |
   | `summary` | text | The recurring themes in a few sentences, plus up to three short quotes |
   | `gatheredAt` | date | When we imported it; the chat's own idea of the date isn't used |

   A landlord row names the landlord in its `summary`. A landlord gets one row per building, not a
   table of its own. Urbane only knows buildings we added, and a landlord table wouldn't matter by
   month five.
2. **The contract gains an optional `reviews` array on each building** (`docs/chat-contract.md`). The
   chat may include only sources it **opened in this conversation**, with the URL of the page it read.
   A remembered or estimated rating is never allowed. Quotes are verbatim, short (under 25 words each)
   and in quotation marks. The summary is the chat's digest, in plain words. Reviews appear only when we
   discussed them or asked for them.
3. **Strict decoding** (jon-platform `semantic-fidelity.md`): a review fails loudly, and is never
   defaulted, if it has an unknown `about`, a missing or non-http(s) URL, a rating without a scale (or
   the reverse), a scale of zero or less, a rating above its scale, or a malformed month.
4. **Re-import replaces a review from the same source and subject.** This is the exception to
   ADR-0006's "fill only empty fields". That rule protects our words; reviews are other people's words,
   and newer is simply better. The bulk review shows each replacement as old → new, checked by default,
   and it can be unchecked. An import never deletes a review whose source isn't in the paste. A review
   top-up is just a normal paste that names the building again.
5. **Shown on the postcard, never averaged.** Each row reads "Openigloo · building · 3.8/5 · 42 reviews ·
   newest Sep 2026 · gathered Nov 2026", then its summary. The source link opens in the in-app browser.
   A row gathered more than six months ago is muted, as rents are (ADR-0003). There's no combined score.
   Sources rate different things on different scales, from different people. A review row can be
   deleted by hand.
6. **The app fetches nothing.** The chat reads public pages in our own conversation, and Urbane stores
   what we reviewed and imported. This isn't AI generation inside the app (PRODUCT.md, ADR-0004). It's
   the same chat-drafts, we-review, app-stores pattern as chapters and summaries.

## Consequences

- One synced table, small text rows, no BLOBs. It fits ADR-0005's tree and the single-FK rule. It's
  additive, so it lands as its own migration in S3 and doesn't touch the S1 migration in PR 2.
- Reviews are only as fresh as our last paste. That's fine: they matter for a handful of tour
  candidates, and a top-up is one chat message.
- If the chat starts making up ratings, the URL rule makes it checkable: every number links to the
  page it came from.
