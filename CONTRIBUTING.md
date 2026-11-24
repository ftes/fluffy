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

## Releasing

The script needs a jj working copy colocated with git, `gh` logged in as a repo admin (to push
`main` past its ruleset and create the tag), and `elixir` on the PATH.

1. `scripts/release --dry-run <version>` runs the checks (an empty `@` on `main@origin` as last
   fetched, a `## Unreleased` with entries, a new tag and a greater version) and prints the
   edits.
2. `scripts/release <version>` commits "Release <version>" (the version, the install line in
   `docs/installation.md` and the dated changelog heading) and "Start the next release", pushes
   them to `main` one at a time and tags the first, which starts `release.yml`. It fetches first
   and checks again. `RELEASE_REMOTE` names another remote than `origin`.
3. Approve the staged release on hex.pm; the workflow then creates the GitHub release.

`## Unreleased` holds every change since the last final release, so after a prerelease "Start
the next release" renames its heading back to `## Unreleased`; after a final release it adds an
empty one. 0.9.0 also ends the release-candidate rules in `AGENTS.md`.

It runs locally, not as a workflow: only an admin can push to `main` past its ruleset, and a tag
pushed with `GITHUB_TOKEN` starts no workflow. `release.yml` publishes only a commit whose CI on
`main` passed, so the release commit is pushed on its own first, and publishing waits for its CI.

`scripts/release.exs` is playwright_ex's script with Fluffy's `ReleaseScript.Config`: keep the
rest the same in both, which is also why `mix format` leaves it out.
