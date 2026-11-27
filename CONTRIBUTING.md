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

## Updating PlaywrightEx

The [PlaywrightEx Release workflow](https://github.com/ftes/fluffy/actions/workflows/playwright-ex-release.yml)
reports newer Hex releases in its run summary. It announces a version once while its Actions cache
marker is retained. Check locally with `python3 dev/playwright_release.py discover`.

From a clean checkout with the usual Fluffy toolchain, run
`python3 dev/playwright_release.py prepare <version>`. It updates `mix.exs`, `mix.lock`,
`mix.lock.oldest`, and `integration/consumer/mix.lock`, then runs `mix setup` and syncs the
generated usage rules. If the new package needs other floor changes, follow the oldest-lock steps
above. CI also verifies the floor with the oldest toolchain.

Review the upstream changes, classify members and events in `test/support/playwright_members.ex`
as needed, and update the changelog or docs if appropriate. Run `mix check` before opening the PR.

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
