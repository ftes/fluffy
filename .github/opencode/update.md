Update Fluffy to the specified PlaywrightEx release from Hex. Read AGENTS.md first.

1. In mix.exs require `{:playwright, "~> TO", hex: :playwright_ex}`, replacing any `github:`
   source, its options and comment. Keep the Hex package name `:playwright_ex`. Run
   `mix deps.update playwright` and read deps/playwright/CHANGELOG.md since FROM. Run
   `mix deps.update playwright` in integration/consumer (use the shell tool's working
   directory), and update the version in docs/installation.md and usage-rules.md.
2. If deps/playwright/DRIVER_VERSION changes, run `mix playwright.install chromium` and
   `mix fluffy.playwright_source`.
3. Run `mix test test/playwright_members_test.exs`. Classify new members and events as
   test/support/playwright_members.ex describes; remove old ones. Wrap only obvious extensions
   of what Fluffy wraps; otherwise classify them, using `gap:` for API candidates.
4. Run `mix usage_rules.sync --yes`.
5. Run `mix check` with Chromium and Postgres. Fix regressions without weakening or skipping
   tests. Rerun failures once with `mix test --failed` and report unrelated remaining failures.
6. Under `## Unreleased` in CHANGELOG.md add "Requires PlaywrightEx TO" and other
   user-visible changes.

Return `publish` with the update title and a short body describing the changes, the `mix check`
result, and any decisions or gaps for a human. The publisher opens a draft PR even if a larger
decision is still needed.
