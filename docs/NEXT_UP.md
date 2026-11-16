# Next Up — A full chat seed resolves without Apple Maps throttling it

**Slices:** effort `import-search-pacing`
**Briefs:** [docs/efforts/import-search-pacing.md](efforts/import-search-pacing.md)
**Done when:** per the brief. The gate passes; the pacer and throttle-wait tests pass on a test clock.
**Owed:** see [device-passes.md](device-passes.md)
**Notes:** Branch `effort/import-search-pacing`. This goes ahead of M1 dispatch 3 because the S3 device pass can't finish until a full seed resolves. Closeout writes the empty ticket; then set `NEXT_UP.md` back to M1 dispatch 3 (S4 + S5) exactly as it reads in commit 20adae4, and re-run `check-handoff --strict`.
