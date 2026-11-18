# Next Up — One patched SQLiteData, kept in jon-platform

**Slices:** effort `shared-sqlitedata-vendor`
**Briefs:** [docs/efforts/shared-sqlitedata-vendor.md](efforts/shared-sqlitedata-vendor.md)
**Done when:** per the brief. Both apps' gates pass, and the workspace resolves with `-scheme Urbane` and `-scheme YesChef`.
**Owed:** see [device-passes.md](device-passes.md)
**Notes:** Three PRs: jon-platform first, then Yes Chef and Urbane, each on `effort/shared-sqlitedata-vendor`. This goes ahead of M1 dispatch 7 (S9) because no scheme in `jon-platform-workspace` builds until it lands. Closeout writes the empty ticket; then set `NEXT_UP.md` to M1 dispatch 6c (S7e), copying its Briefs line from the milestone's Dispatches list word for word, and re-run `check-handoff --strict`. S9 (dispatch 7) follows S7e.
