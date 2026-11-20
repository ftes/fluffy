# Developing Fluffy

The project pins the current local-development toolchain in `.tool-versions`.
Fluffy's compatibility floor is Elixir 1.18 on OTP 27 with Phoenix 1.7.24 and LiveView
1.2.10 (`.tool-versions.oldest` and `mix.lock.oldest`, which CI's oldest lane uses);
development also requires PostgreSQL. From a clean checkout:

```bash
mix setup
mix test
```

`mix.lock.oldest` is a lock with Phoenix and LiveView at their floors. To move one,
require exactly the new floor in `mix.exs`, copy `mix.lock.oldest` to `mix.lock`, run
`mix deps.update phoenix phoenix_live_view`, keep the result as `mix.lock.oldest`, and
restore `mix.lock` and the requirement.

`mix setup` installs Chromium and fetches Playwright's source, for reference, into
`tmp/playwright-<version>`. To run the suite on Firefox or WebKit, install it with
`mix playwright.install firefox` (or `webkit`) and set `FLUFFY_BROWSER=firefox`.

Upstream Playwright's behavior is the reference for Fluffy's, and Phoenix LiveView's the
secondary one for the Phoenix drivers; see `AGENTS.md`.

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
