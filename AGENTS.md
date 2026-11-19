# Fluffy repository instructions

Phoenix feature tests: one Playwright-shaped API over three drivers (Static, LiveView,
Playwright).

Treat observable public behavior as the contract. Keep driver-specific
boundaries explicit and cover behavior changes with focused conformance tests.

Upstream Playwright is the reference. Fluffy is modeled on Playwright and adds only what Phoenix
LiveView needs (waiting for LiveViews to connect, following their navigations, form state). The
exceptions are `Fluffy.submit/3` and the `Fluffy.PhoenixTest` facade, kept for suites coming from
PhoenixTest; don't grow them into a second API. Before adding a timeout budget, retry, extra check
or browser workaround, check what Playwright does and match it; the pinned source is in
`tmp/playwright-<version>` (`mix setup` or `mix fluffy.playwright_source` fetches it) and
dependency code in `deps/`, both gitignored, so Grep needs their path. Don't work around Playwright, its Elixir client or browser bugs (upstream
`fixme` tests mark the known ones); let Playwright's behavior show through. Only as a last resort,
when LiveView support can't work without it, add a workaround, and say why in a comment. Build
Playwright selectors through the Elixir client (its `Frame`/`Locator`/`FrameLocator` API,
`Isomorphic.LocatorUtils` and `SelectorParser`); don't write selector strings in Fluffy, since
`internal:*` engine syntax changes between Playwright versions.
Timeouts follow Elixir: `0` means check once and `:infinity` means no limit;
`Fluffy.Deadline.playwright/1` maps `0` to 1ms, since Playwright's 0 means no limit.

Phoenix upstream is the secondary reference, for the Phoenix drivers. Playwright decides what
behavior is correct; LiveView's client JS and `Phoenix.LiveViewTest` decide how the Phoenix drivers
get there. Build on LiveViewTest rather than reimplementing it. Work around its limitations when a
test would see the browser behave differently, matching the browser and mirroring LiveView's JS.
A difference may stay when it's an edge case most users won't hit, or when closing it is very
complicated; document the differences you leave. Ask the maintainer before building a complex
workaround.

Run `mix check` before handing off code changes. It runs what CI's checks job runs (formatting,
warnings-as-errors compilation, the usage rules check, Credo, the docs build, Dialyzer) and the
test suite. When reviewing a change or fixing review findings, follow
[Reviewing](CONTRIBUTING.md#reviewing).

0.9 is a breaking release candidate: don't add compatibility code for earlier versions or release
candidates (deprecations, aliases, fallbacks for removed options). A change users can see gets an
entry under `## Unreleased` in `CHANGELOG.md`, written as a change from the last release (0.8.0),
and, if it breaks a suite, a step in `docs/upgrading.md`. Refactors, tests, docs fixes and CI
changes get no entry.

- `mix setup` installs deps, builds test assets and installs Chromium. Tests need PostgreSQL
  (`FLUFFY_DB_*` overrides the defaults in `config/test.exs`); `FLUFFY_BROWSER` picks
  firefox or webkit.
- Tests in `test/conformance/` run the same behavior against several drivers. The matrix in
  `docs/capabilities.md` is rendered from `Fluffy.Capability`, and a test keeps them in sync.
- Docs, doc examples and test fixtures follow the Fluffy / Harry Potter theme; keep new examples on theme.
- `.agents/skills` (linked from `.claude/skills`) is generated: after updating deps run
  `mix usage_rules.sync --yes`; `mix check` fails when it's stale. On Renovate's PRs a workflow
  commits it. The `phoenix` skill's rules are written for applications, so in this library
  they mainly apply to the fixtures under `test/`.
- The compatibility floor is Elixir 1.18 on OTP 27 (`.tool-versions.oldest`).
