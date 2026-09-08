# Fluffy

![A friendly three-headed Fluffy asleep beside an Elixir wizard playing a flute, with the heads labeled Live, Static, and Playwright](docs/images/fluffy-banner.webp)

**Phoenix feature testing — 3 drivers, 1 API: Static, LiveView, Playwright.**

[![Hex.pm](https://img.shields.io/hexpm/v/fluffy.svg)](https://hex.pm/packages/fluffy)
[![HexDocs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://fluffy.hexdocs.pm/)
[![CI](https://github.com/ftes/fluffy/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ftes/fluffy/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)

Write blazing-fast Phoenix feature tests with one unified, Playwright-shaped
API. Composable locators and strict actions keep driver-specific escape hatches
rare. Keep the same readable pipeline across controller-rendered pages,
LiveView, and a real browser.

## This is what it looks like

```elixir
start_session(:phoenix)
|> visit("/creatures")
|> fill(by_label("Name"), "Basilisk")
|> click(by_role(:button, name: "Register"))
|> expect(by_role(:heading, name: "Basilisk") |> to_be_visible())
|> expect(Page.to_have_url("/creatures/basilisk"))
```

Fluffy has two backends: Phoenix (`:phoenix`) and Playwright (`:playwright`).
The Phoenix backend stays in-process and selects the Static
(`Phoenix.ConnTest`) or LiveView (`Phoenix.LiveViewTest`) driver for each page.
The same session can move between them as navigation changes pages.

The Playwright backend runs the Playwright driver in a real browser, where it
can verify JavaScript hooks, layout, and browser behavior:

```elixir
start_session(:playwright)
|> visit("/creatures/fluffy")
|> click(by_role(:button, name: "Play flute"))
|> expect(by_text("Fluffy is asleep") |> to_be_visible())
```

An extensive browser-backed conformance suite verifies that the Phoenix
backend matches Playwright within the documented capability boundaries.

Fluffy uses Playwright's locator, strictness, assertion, and retry model as
its baseline:

- Locators are semantic and composable.
- Single-target actions are strict.
- LiveView and Playwright operations retry within their documented boundaries;
  Static operations are immediate.

## Who is this for?

**PhoenixTest users who want Playwright semantics, not just browser access.**
PhoenixTest can already add browser coverage through `phoenix_test_playwright`.
Fluffy instead shapes its shared API around Playwright: composable locators,
strict actions, and portable expectations mean fewer trips through native
`unwrap/2` escape hatches. An extensive browser-backed conformance corpus keeps
the Static and LiveView drivers aligned within the documented capability
boundaries.

**Phoenix teams assembling their own feature-test stack.** Fluffy replaces the
usual mix of `ConnCase`, `Phoenix.LiveViewTest`, and browser helpers with one
test vocabulary across controller pages, LiveView, and Playwright.

**Teams that want fast tests without invented browser behavior.** The Static
and LiveView drivers implement a documented, browser-validated subset of
locator matching, actionability, forms, navigation, and events. Use Playwright
for the remaining browser-owned behavior instead of running every feature test
there.

## Getting started

Add the dependency:

```elixir
# mix.exs
defp deps do
  [
    {:fluffy, "~> 0.2.0", only: :test}
  ]
end
```

Configure the endpoint:

```elixir
# config/test.exs
config :fluffy, endpoint: MyAppWeb.Endpoint
```

Every Fluffy test establishes a lifecycle scope and imports the shared API:

```elixir
use ExUnit.Case, async: true

import Fluffy
import Fluffy.Expect
import Fluffy.Locator

alias Fluffy.Page

setup context do
  Fluffy.Test.setup(context)
end
```

Start with `start_session(:phoenix)`. It runs entirely in Elixir and starts no
Node process or browser. To use the Playwright backend, install Playwright in
the application and configure its CLI path:

```bash
pnpm add --save-dev playwright@1.63.0
pnpm exec playwright install chromium
```

```elixir
# config/test.exs

config :my_app, MyAppWeb.Endpoint, server: true

config :fluffy,
  playwright: [
    enabled: true,
    executable: Path.expand("../node_modules/playwright/cli.js", __DIR__),
    engine: :chromium,
    launch_options: [headless: true]
  ]
```

Then change only the backend:

```elixir
start_session(:playwright)
```

Applications using Ecto need one additional sandbox bridge so browser and
LiveView processes share the test checkout. See
[Installation and runtime](docs/installation.md) for the complete setup,
options, failure artifacts, and alternate browser engines.

## Migrating from PhoenixTest

Fluffy is a close relative, not a compatibility wrapper. The broad shape is
familiar—visit a page, interact, assert, keep piping—but the vocabulary follows
Playwright's locator model:

| PhoenixTest | Fluffy |
| --- | --- |
| `conn \|> visit("/creatures")` | `start_session(:phoenix) \|> visit("/creatures")` |
| `click_link("Creatures")` | `click(by_role(:link, name: "Creatures"))` |
| `click_button("Register")` | `click(by_role(:button, name: "Register"))` |
| `fill_in("Name", with: "Basilisk")` | `fill(by_label("Name"), "Basilisk")` |
| `assert_has(".creature", "Basilisk")` | `expect(by_text("Basilisk") |> to_be_visible())` |
| `within("#potions", fn session -> ... end)` | compose a child locator under `by_css("#potions")` |
| `submit()` | `submit(form_locator)` or click the intended submit button |
| `reload_page()` | `reload()` |
| `at: 1` | `nth(locator, 0)` |

The changes buy a few useful things out of the box:

- **One API includes the browser.** Keep fast Static and LiveView tests, then use
  the same pipeline for JavaScript, dialogs, layout, and network behavior.
- **Playwright-style locators everywhere.** Prefer roles, accessible names,
  labels, and text; compose locators as values; get a strictness error instead
  of an arbitrary first match.
- **Waiting belongs to the library.** The LiveView and Playwright drivers react
  to async renders and automatically await LiveView connection.

See [Migrating from PhoenixTest](docs/migration-from-phoenix-test.md).

## Advanced features: two backends, three drivers

Select the Phoenix or Playwright backend when starting a session. The Phoenix
backend chooses the Static or LiveView driver for each page; the Playwright
backend uses the Playwright driver.

| Feature | Phoenix | Playwright |
| --- | --- | --- |
| Semantic locators, actions, and assertions | supported structural model | native browser behavior |
| Controller navigation, forms, redirects, and cookies | supported across Static and LiveView documents | supported |
| LiveView events, patches, navigation, and retry | supported | supported through the browser |
| `data-method` / `data-to` actions | stock Phoenix.HTML structural model | native Phoenix.HTML JavaScript |
| Dialogs and `data-confirm` | action continues; no dialog is invented | capture, accept, or dismiss |
| Downloads | declarative downloads | supported |
| File selection and uploads | typed paths/payloads, multipart forms, and the supported managed LiveView lifecycle | native typed selection and scripted chooser capture |
| Multiple tabs/pages | - | supported, including script-created pages |
| Multiple isolated user sessions | supported | one isolated BrowserContext per session |
| Request/response events | - | supported |
| Arbitrary application JavaScript | - | supported |

Advanced events use listener-before-action orchestration, so Fluffy starts
listening before the click that causes them:

```elixir
alias Fluffy.Event

session
|> wait_for(Event.download(:report), fn session ->
  click(session, by_role(:button, name: "Download potion ledger"))
end)
|> expect(to_have_download_suggested_filename(:report, "potions.csv"))
```

See [Advanced events and pages](docs/advanced-events.md) for downloads,
dialogs, navigation, tabs, and network events. The full, versioned truth table
lives in the [Capability matrix](docs/capabilities.md). When in doubt, consult
the matrix.

## Guides

- [Installation and runtime](docs/installation.md) — endpoint, browser, and
  Ecto sandbox setup
- [Usage](docs/usage.md) — locators, actions, expectations, backend choice, and
  diagnostics
- [Advanced events and pages](docs/advanced-events.md) — downloads, tabs,
  navigation, dialogs, and network events
- [Capability matrix](docs/capabilities.md) — the precise backend and driver boundaries
- [Migrating from PhoenixTest](docs/migration-from-phoenix-test.md) — practical
  conversion guidance

## Developing Fluffy

The project pins the current local-development toolchain in `.tool-versions`.
Fluffy's compatibility floor remains Elixir 1.18 and Node.js 20; development
also requires pnpm 11.19.0 and PostgreSQL. From a clean checkout:

```bash
mix setup
mix test
```

Run the ordinary local gate—Styler-backed formatting, warnings-as-errors
compilation, strict Credo, and the test suite—with:

```bash
mix check
```

Add test-environment Dialyzer analysis with:

```bash
mix quality
```

## License

Fluffy is released under the [MIT License](LICENSE.md).
