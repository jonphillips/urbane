# Next Up — The building postcard and neighborhood chapters

**Slices:** M1 · S4 + S5
**Briefs:** docs/milestones/M1-browse.md §S4 and §S5, docs/decisions/0002-imagery-from-apple-frameworks.md, docs/decisions/0004-words-are-ours.md, docs/decisions/0007-building-reviews-from-chat.md
**Done when:** per the brief. The gate passes; a building with no hero image and no Look Around coverage still looks good, and an imported chapter keeps its paragraphs exactly as written.
**Owed:** see [device-passes.md](device-passes.md)
**Notes:** Local-only; S7 turns sync on. S4 starts with ADR-0002's two-candidate proof for Look Around and builds the one that works. Reuse the place-search dependency from S2/S3 for vignettes. Also, a small S3 fix to ride along: a JSON decoding failure in Import from chat surfaces Swift's generic message ("The data couldn't be read because it is missing.") with no location, because `ChatImportDecoder.decode` wraps it as `invalidPaste(error.localizedDescription)`. Map `DecodingError` to `invalidRow` with its coding path and the reason (missing key, null where a value is required, wrong type), e.g. "buildings[0].reviews[0].url: required, got null". Add fixtures for a null review `url` and a missing building `summary` key.
