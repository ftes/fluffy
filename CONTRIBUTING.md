# Developing Fluffy

The project pins the current local-development toolchain in `.tool-versions`.
Fluffy's compatibility floor is Elixir 1.18 on OTP 27 with Phoenix 1.7.10 and LiveView
1.1.32 (`.tool-versions.oldest` and `mix.lock.oldest`, which CI's oldest lane uses);
development also requires PostgreSQL. From a clean checkout:

```bash
mix setup
mix test
```

`mix.lock.oldest` locks every direct runtime dependency at its floor, the lowest version its
requirement in `mix.exs` accepts, which `DependencyFloorsTest` checks. To move one, copy
`.tool-versions.oldest` to `.tool-versions` and `mix.lock.oldest` to `mix.lock`, require
exactly the new floor, run `mix deps.update <dep>`, restore the requirement, and keep the
lock as `mix.lock.oldest` once `mix deps.get --check-locked` accepts it from an empty `deps/`,
as CI runs it. Then restore `.tool-versions` and `mix.lock`.
Renovate never updates `mix.lock.oldest`. When `mix.exs` no longer accepts what it locks (a raised
floor, or a dev dependency's new major), CI's oldest lane fails at setup with "deps.get changed
mix.lock.oldest"; update the lock as above.

`mix setup` installs Chromium and fetches Playwright's source, for reference, into
`tmp/playwright-<version>`. To run the suite on Firefox or WebKit, install it with
`mix playwright.install firefox` (or `webkit`) and set `FLUFFY_BROWSER=firefox`.

Upstream Playwright's behavior is the reference for Fluffy's, and Phoenix LiveView's the
secondary one for the Phoenix drivers; see `AGENTS.md`.

The layers of the code, and where a new feature belongs, are in [Architecture](AGENTS.md#architecture).

Run the local gate, the same checks CI runs (Styler-backed formatting, warnings-as-errors
compilation, the usage rules check, strict Credo, the docs build and Dialyzer), then the test
suite, with:

```bash
mix check
```

`mix lint` runs the checks without the tests. Rules for compatibility code and the changelog are
in `AGENTS.md`.

## Updating PlaywrightEx

Maintainers can run **PlaywrightEx Update Pilot** on the default branch from Actions with an
exact newer Hex release. It checks the prepared update with `mix check` before opening a draft
with the normal PR checks. PlaywrightEx dependency and inventory changes use manual review.
Review the member classifications and release notes before marking it ready. A repeated release
with an existing pilot PR is skipped. If a run pushes the branch
but stops before opening the PR, inspect the branch before removing it and dispatching again.

To prepare the requirement, lockfiles and usage rules locally, run
`elixir dev/playwright_release.exs prepare <version>`.

## Trying the improvement pilot

Maintainers can run **Fluffy Improvement Pilot** on the default branch from Actions.
Claude Code can propose one documentation improvement to the locator guide or decline.
It skips inference if the paragraph's text has changed, ignoring line wrapping.
It also skips if an improvement pilot PR is already open against the same base.
An isolated docs build checks any proposal before a draft opens with normal PR checks.
Review and decide what to do with the draft yourself. If a run pushes a branch but does
not open a draft, inspect it before trying again.

## Terms

In docs, a *backend* is what `start_session` picks, Phoenix or Playwright; a *driver* runs a
page: Static and LiveView (the Phoenix drivers) or Playwright. What only a browser can do is
*Playwright only*, as ex_doc's annotation says.

## Reviewing

Besides correctness, review a change for simplicity, consistency and scope. This applies to
human and agent reviews alike.

- Prefer the change that removes or shares code over one that adds a parallel path; a rule all
  drivers follow belongs in one place, not in each driver.
- Follow how the codebase already does the same thing. A new pattern needs a reason.
- A PR fixes its issue. Edge cases and gaps that predate it are follow-ups: note them
  instead of adding code for them in the PR.

## Asking the agent

Maintainers can use `/agent` followed by a request in an issue, PR comment, or review.
The command works on pull requests from this repository.

## Releasing

Releases run from a checkout of [ftes/ci](https://github.com/ftes/ci), with `gh` logged in as a
repo admin (to push `main` past its ruleset and create the tag) and `jj` and `elixir` on the PATH:

```sh
# Makes both commits in a clone and prints them; pushes nothing.
release/release.exs fluffy --dry-run <version>
release/release.exs fluffy <version>
```

It clones this repo into a temporary directory, commits "Release <version>" and "Start the next
release", pushes `main` and tags the first commit. The tag runs CI (`ci.yml`) on the tagged
commit; once every job passed, its publish job stages the release on Hex. Approve it on hex.pm;
the job then creates the GitHub release.

`## Unreleased` gathers every change since the last final release, across the release candidates.
For a final release, drop the `**RC only:**` entries first: the script refuses while they remain.
0.9.0 also ends the release-candidate rules in `AGENTS.md`. `release/release.exs` lists the
conventions it relies on.
