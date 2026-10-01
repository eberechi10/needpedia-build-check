# needpedia-build-check

Public daily build check for [Needpedia](https://github.com/Queuevius/Needpedia).
It runs on GitHub Actions, needs no secrets or tokens, and keeps
`results/latest.json` + `results/history.csv` up to date in this repo.

## What it does

Every day (and whenever someone presses **Run workflow**):

1. **build** — checks out Needpedia's default branch and builds its own
   `Dockerfile`, unchanged.
2. **database** — starts PostgreSQL 13 and Redis 7, waits for both, then
   runs `rails db:create db:migrate`.
3. **start** — starts the web container.
4. **page** — loads `http://localhost:3000/` and requires HTTP 200.

Any failure is recorded as a `failed_step` of `build`, `database`, `start`,
or `page`, with the last ~30 lines of that step's log.

## Settings

Open `.github/workflows/build-check.yml` and edit the block at the top:

| Setting | Current value | Meaning |
| --- | --- | --- |
| `NEEDPEDIA_REPO` | `Queuevius/Needpedia` | which project to check |
| `NEEDPEDIA_BRANCH` | `master` | Needpedia's default branch |

## Why it is red right now

Since 31 Aug 2026 the build fails at the `apt-get` step because Debian 11
(bullseye) reached end-of-life and its packages moved to the archive.
[PR #195](https://github.com/Queuevius/Needpedia/pull/195) fixes it. This
check deliberately does **not** apply that fix, so until it is merged expect
`"passed": false, "failed_step": "build"`. That is the check working — it
turns green by itself once the fix is merged.

## Result files

`results/latest.json` — fields (do not rename them; Tony's activity page
reads them):

- `checked_at` — date and time of the run (UTC, ISO 8601)
- `passed` — true or false
- `failed_step` — `build`, `database`, `start`, or `page` (empty when passed)
- `error_lines` — last ~30 lines of the failing step
- `needpedia_commit` — full commit SHA of Needpedia that was tested
- `run_url` — link to this run on GitHub
- `last_passed_at` — when the check last passed (null if never)

`results/history.csv` — one line per run with the scalar fields.

## Running by hand

**Actions** tab → **Daily Needpedia build check** → **Run workflow** →
**Run workflow**. The run records its result whether it passes or fails.

## Transfer

This repo keeps working unchanged after GitHub *Settings → Transfer
ownership*. No secrets are used and nothing depends on the original owner's
account.
