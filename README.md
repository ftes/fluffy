# Fluffy

![A friendly three-headed Fluffy asleep beside an Elixir wizard playing a flute, with the heads labeled Live, Static, and Playwright](https://raw.githubusercontent.com/ftes/fluffy/main/docs/images/fluffy-banner.webp)

**Phoenix feature tests. Three drivers, one Playwright-shaped API.**

[![Hex.pm](https://img.shields.io/hexpm/v/fluffy.svg)](https://hex.pm/packages/fluffy)
[![HexDocs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://fluffy.hexdocs.pm/)
[![CI](https://github.com/ftes/fluffy/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ftes/fluffy/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)

Start with `:phoenix` to test controller pages and LiveViews in-process. Switch to
`:playwright` when a test needs JavaScript, CSS layout, or other browser behavior.
The actions and assertions stay the same:

```elixir
creature_row =
  by_role(:table, "Hagrid's creatures")
  |> by_role(:row)
  |> filter(has: by_text("Fluffy", exact: true))

start_session(:phoenix)
|> visit("/creatures")
|> click(button(creature_row, "Play flute"))
|> assert_has(by_role(creature_row, :cell, "Asleep"))
```

[Install Fluffy](docs/installation.md), then follow [Your first test](docs/usage.md#your-first-test)
for the imports and session setup used above.

Coming from PhoenixTest? The [migration guide](docs/migration-from-phoenix-test.md)
shows how to rewrite tests or keep familiar helpers with the facade. For an existing
Fluffy suite, see [Upgrading to 0.9](docs/upgrading.md).

## Guides

- [Why Fluffy](docs/why-fluffy.md) — the problem it solves, how it compares with
  PhoenixTest and PhoenixTest.Playwright, and its trade-offs
- [Installation and runtime](docs/installation.md) — endpoint, browser,
  Ecto sandbox setup, and usage rules for coding agents
- [Usage](docs/usage.md) — your first test, backend choice, and a shared test case
- [Locators and frames](docs/locators.md) — finding elements and reaching into iframes
- [Actions and waiting](docs/actions.md) — actions, waiting, uploads, and controlling time
- [Assertions](docs/assertions.md) — `assert` and `refute`, visibility, and page assertions
- [Debugging and native access](docs/debugging.md) — failures, browser diagnostics,
  and the native escape hatch
- [Advanced events and pages](docs/advanced-events.md) — tabs, windows, iframe
  limitations, downloads, navigation, dialogs, and network events
- [Capability matrix](docs/capabilities.md) — backend differences and limitations

See [CONTRIBUTING.md](https://github.com/ftes/fluffy/blob/main/CONTRIBUTING.md) for developing Fluffy itself.

## License

Fluffy is released under the [MIT License](LICENSE.md).
