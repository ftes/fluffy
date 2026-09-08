# Fluffy

![A friendly three-headed Fluffy asleep beside an Elixir wizard playing a flute, with the heads labeled Live, Static, and Playwright](docs/images/fluffy-banner.webp)

**Phoenix feature tests. Three drivers, one Playwright-shaped API.**

[![Hex.pm](https://img.shields.io/hexpm/v/fluffy.svg)](https://hex.pm/packages/fluffy)
[![HexDocs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://fluffy.hexdocs.pm/)
[![CI](https://github.com/ftes/fluffy/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ftes/fluffy/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)

Fluffy runs tests through ConnTest, LiveViewTest, or a real browser. Its
in-process drivers are checked against Playwright, grounding their behavior
in browser reality.

**Coming from PhoenixTest?** Fluffy adds strict, composable locators, per-test
backend selection within one module, and Playwright-style assertion retries
and action waiting. [See the differences →](docs/migration-from-phoenix-test.md)

```elixir
start_session(:phoenix)
|> visit("/creatures")
|> fill(by_label("Name"), "Basilisk")
|> click(by_role(:button, name: "Register"))
|> expect(by_role(:heading, name: "Basilisk") |> to_be_visible())
|> expect(Page.to_have_url("/creatures/basilisk"))
```

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

Start with `start_session(:phoenix)` for in-process Static and LiveView tests.
Use `start_session(:playwright)` when a test needs a real browser. See
[Installation and runtime](docs/installation.md) for Playwright and Ecto sandbox
setup, then [Usage](docs/usage.md) for writing tests and a shared `FluffyCase`.

## Migrating from PhoenixTest

The pipeline stays familiar; actions and expectations use composable locators:

| PhoenixTest | Fluffy |
| --- | --- |
| `fill_in("Name", with: "Basilisk")` | `fill(by_label("Name", exact: true), "Basilisk")` |
| `click_button("Register")` | `click(by_role(:button, name: "Register"))` |
| `assert_path("/creatures")` | `expect(Page.to_have_url(path: "/creatures"))` |

See [Migrating from PhoenixTest](docs/migration-from-phoenix-test.md) for the
full translation table and behavior differences.

## Beyond page interactions

Capture downloads, open new tabs, handle dialogs, and observe network events
with Fluffy's event API. See [Advanced events and pages](docs/advanced-events.md)
for examples and the [Capability matrix](docs/capabilities.md) for what each
backend supports.

## Guides

- [Installation and runtime](docs/installation.md) — endpoint, browser, and
  Ecto sandbox setup
- [Usage](docs/usage.md) — locators, actions, expectations, backend choice, and
  diagnostics
- [Advanced events and pages](docs/advanced-events.md) — downloads, tabs,
  navigation, dialogs, and network events
- [Migrating from PhoenixTest](docs/migration-from-phoenix-test.md) — an alternate
  starting point for existing PhoenixTest suites
- [Capability matrix](docs/capabilities.md) — backend differences and limitations

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
