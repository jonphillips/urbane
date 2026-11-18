# Effort — Rotate JON_PLATFORM_PAT from one command

Status: Ready
Summary: Every app's CI clones private jon-platform with its own copy of `JON_PLATFORM_PAT`, because a personal account has no shared Actions secrets. On 2026-11-16 the token was regenerated and set on five repos. Yes Chef was missed, and its CI failed on 2026-11-18 with a bare `Invalid username or token`. Add `jon-platform/scripts/platform-pat`, which sets the token on every consumer from one prompt and reports any repo left stale, and make the CI failure name the fix.

Related: [shared-sqlitedata-vendor](archive/shared-sqlitedata-vendor.md), where the failure surfaced on Yes Chef #532 ·
jon-platform `docs/ios/drift-control.md` (the CI setup) · [Efforts index](README.md)

Three PRs: jon-platform and `ci-workflows` first, in either order, then the Urbane companion PR for the
records (jon-platform `agent-collaboration.md` § Dispatches whose code lands in jon-platform). Branch
`effort/platform-pat` in each repo, from a fresh `main`. No app code changes.

## Why

`secrets: inherit` passes each caller's own secrets, and account-wide Actions secrets exist only for
organizations, so each app repo has to hold a copy. Regenerating a PAT kills the old value at once. The Nov 16
rotation updated urbane, galavant, fit-happens, cockpit and vinyl-fever, but yes-chef kept the Aug 24
value. Nothing reported the stale copy until a PR's test job failed. Then the CI error didn't say which
secret was rejected or how to fix it, which cost a `question-for-architect` round.

Consumers today, meaning repos with a workflow that calls `jonphillips/ci-workflows`: urbane, galavant,
fit-happens, yes-chef and cockpit. vinyl-fever holds the secret but has no workflows.

## Changes

1. **jon-platform: `scripts/platform-pat`**, written for bash 3.2, with a header comment like the other
   scripts.
   - **Consumers** are the non-archived `jonphillips` repos that have a file under `.github/workflows/`
     that references `jonphillips/ci-workflows/`. Find them through `gh api` at run time, never from a
     list in the script. Skip `ci-workflows` itself.
   - **`platform-pat set`** reads the token once. From a terminal, read it with `read -rs` and no echo.
     Otherwise read it from stdin, so `op read … | platform-pat set` works. Before setting anything,
     check that the token can read jon-platform: a `GET` of
     `repos/jonphillips/jon-platform/contents/AGENTS.md` through `curl`, with the auth header passed on
     stdin. If that fails, stop with a message and change nothing. Then pipe the token to
     `gh secret set JON_PLATFORM_PAT -R jonphillips/<repo>` for each consumer, and print one line per
     repo. Exit 1 if any repo failed.
   - **`platform-pat check`** prints each consumer's `JON_PLATFORM_PAT` `updated_at`, from
     `repos/<repo>/actions/secrets/JON_PLATFORM_PAT`. It marks a consumer with no secret `missing`, and
     one set more than 7 days before the newest `stale`. Set the window with `PLATFORM_PAT_STALE_DAYS`.
     A hand-set straggler can't be told apart by value, only by date, so the window has to absorb a
     catch-up like today's: yes-chef was set Nov 18 and the rest Nov 16, all with the same token. The
     Aug 24 copy was 84 days behind. Exit 1 if any consumer is missing or stale. Repos that hold the
     secret but aren't consumers get an `unused` line, for information only: they don't change the
     exit code.
   - **The token** never appears on a command line, in a file, or in output. Nothing in the script
     stores it.
   - **`-n`** prints what `set` would do, including the consumer list, without checking the token or
     setting anything. That matches the other scripts.
2. **jon-platform: test** in `scripts/tests/platform-pat.sh`, with stub `gh` and `curl` like
   `worktree-audit.sh`. Cover: consumer discovery, which skips a repo with no workflows and one whose
   workflows don't call ci-workflows; a rejected token, which sets nothing and exits 1; a good token,
   which sets every consumer, never puts the token in any stub's arguments, and exits 0; and `check`
   reporting `stale`, `missing` and `unused`, with the right exit codes. Include two dates 2 days apart
   (not stale) and two 84 days apart (stale).
3. **jon-platform: docs.** Add a row to `scripts/README.md`. In `docs/ios/drift-control.md`, change the
   "Add the `JON_PLATFORM_PAT` secret" setup step to run `platform-pat set`, and add a sentence on
   rotating: regenerate the PAT, run `platform-pat set`, then `platform-pat check`.
4. **ci-workflows: name the fix.** In `ios-ci.yml`'s "Check out jon-platform" step, when the clone
   fails, print a `::error::` that says `JON_PLATFORM_PAT` was rejected or is empty, and to run
   `~/code/jon-platform/scripts/platform-pat set`, then exit non-zero as it does today. Point the
   header's "One-time setup" comment at the same command. Change nothing else in the workflow.

## Done when

- **jon-platform PR:** `scripts/tests/platform-pat.sh` passes, and so does every other
  `scripts/tests/*.sh`. `scripts/check-index` reports nothing new. `platform-pat -n set` lists the five
  consumers above. `platform-pat check` exits 0 and marks vinyl-fever `unused`. Paste the output of both into the PR body. Don't run
  a real `set`: Jon runs that at his next rotation.
- **ci-workflows PR:** run the edited step's script locally with a bogus `JON_PLATFORM_PAT`, and with an
  empty one, and paste the `::error::` lines into the PR body. After it merges, the Urbane PR's own CI
  run shows that the success path is unchanged.
- **Urbane PR:** CI is green, and the PR runs closeout (ADR-0005 D16), naming all three PRs in its
  DONE-LOG entry.

**Escalated to Jon:** shared tooling in jon-platform, and a workflow that every app's CI calls from
`@main`. No schema, sync or device gate.

## Not in this effort

- Moving the repos into a GitHub organization to get one shared secret, or replacing the PAT with a
  GitHub App. Both are bigger than one rotation every few months.
- Running `platform-pat check` from `orient`. It makes a network call per repo on every orient, and the
  CI error now names the fix.
- Storing the token anywhere: Keychain, a file or an environment variable.
