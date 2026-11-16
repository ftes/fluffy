# Developing Fluffy

The project pins the current local-development toolchain in `.tool-versions`.
Fluffy's compatibility floor is Elixir 1.18 on OTP 27; development also
requires PostgreSQL. From a clean checkout:

```bash
mix setup
mix test
```

`mix setup` installs Chromium and fetches Playwright's source, for reference, into
`tmp/playwright-<version>`. To run the suite on Firefox or WebKit, install it with
`mix playwright.install -- firefox` (or `webkit`) and set `FLUFFY_BROWSER=firefox`.

Upstream Playwright's behavior is the reference for Fluffy's, and Phoenix LiveView's the
secondary one for the Phoenix drivers; see `AGENTS.md`.

Run the ordinary local gate—Styler-backed formatting, warnings-as-errors
compilation, strict Credo, and the test suite—with:

```bash
mix check
```

Add test-environment Dialyzer analysis with:

```bash
mix quality
```

## Reviewing

Besides correctness, review a change for simplicity, consistency and scope. This applies to
human and agent reviews alike.

- Prefer the change that removes or shares code over one that adds a parallel path; a rule all
  drivers follow belongs in one place, not in each driver.
- Follow how the codebase already does the same thing. A new pattern needs a reason.
- A PR fixes its issue. Edge cases and gaps that predate it are follow-ups: note them
  instead of adding code for them in the PR.
