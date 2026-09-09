# Fluffy

![A friendly three-headed Fluffy asleep beside an Elixir wizard playing a flute, with the heads labeled Live, Static, and Playwright](docs/images/fluffy-banner.webp)

**Phoenix feature tests. Three drivers, one Playwright-shaped API.**

[![Hex.pm](https://img.shields.io/hexpm/v/fluffy.svg)](https://hex.pm/packages/fluffy)
[![HexDocs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://fluffy.hexdocs.pm/)
[![CI](https://github.com/ftes/fluffy/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ftes/fluffy/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)

Fluffy runs tests through ConnTest, LiveViewTest, or a real browser. Its
in-process drivers are checked against Playwright. Driver differences are
documented in the [capability matrix](docs/capabilities.md).

**Coming from PhoenixTest?** Fluffy adds strict, composable locators, per-test
backend selection within one module, and assertion retries and action waiting
for LiveView and browser tests. [See the differences →](docs/migration-from-phoenix-test.md)

```elixir
creature_row =
  by_role(:table, name: "Hagrid's creatures")
  |> by_role(:row)
  |> filter(has: by_text("Fluffy", exact: true))

start_session(:phoenix)
|> visit("/creatures")
|> click(by_role(creature_row, :button, name: "Play flute"))
|> assert(visible(by_role(creature_row, :cell, name: "Asleep")))
```

This example assumes the imports and test setup below. Locators are reusable
queries: find Fluffy's row in the “Hagrid's creatures” table and scope both the
action and the assertion to it.

<details>
<summary>HTML behind this example</summary>

<pre>
<code class="language-html">
&lt;h1 id="guards-heading"&gt;Hagrid's creatures&lt;/h1&gt;
&lt;table aria-labelledby="guards-heading"&gt;
  &lt;thead&gt;
    &lt;tr&gt;&lt;th&gt;Creature&lt;/th&gt;&lt;th&gt;State&lt;/th&gt;&lt;th&gt;Actions&lt;/th&gt;&lt;/tr&gt;
  &lt;/thead&gt;
  &lt;tbody&gt;
    &lt;tr&gt;
      &lt;td&gt;Norbert&lt;/td&gt;
      &lt;td&gt;Awake&lt;/td&gt;
      &lt;td&gt;
        &lt;form method="post" action="/creatures"&gt;
          &lt;input type="hidden" name="creature" value="norbert"&gt;
          &lt;button name="action" value="feed"&gt;Feed dragon&lt;/button&gt;
        &lt;/form&gt;
      &lt;/td&gt;
    &lt;/tr&gt;
    &lt;tr&gt;
      &lt;td&gt;Fluffy&lt;/td&gt;
      &lt;td&gt;Awake&lt;/td&gt;
      &lt;td&gt;
        &lt;form method="post" action="/creatures"&gt;
          &lt;input type="hidden" name="creature" value="fluffy"&gt;
          &lt;button name="action" value="flute"&gt;Play flute&lt;/button&gt;
        &lt;/form&gt;
      &lt;/td&gt;
    &lt;/tr&gt;
  &lt;/tbody&gt;
&lt;/table&gt;
</code>
</pre>

</details>

## Getting started

Add the dependency:

```elixir
# mix.exs
defp deps do
  [
    {:fluffy, "~> 0.3.0", only: :test}
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
use Fluffy.Assert

import Fluffy
import Fluffy.Locator

setup context do
  Fluffy.Test.setup(context)
end
```

Start with `start_session(:phoenix)` for in-process Static and LiveView tests.
Use `start_session(:playwright)` when a test needs a real browser. See
[Installation and runtime](docs/installation.md) for Playwright and Ecto sandbox
setup, then [Usage](docs/usage.md) for writing tests and a shared `FluffyCase`.

## Assertion styles

The guides use ExUnit-style assertions. Both styles use the same execution
engine, retries, and diagnostics; this is just a choice of vocabulary.

| ExUnit style — `use Fluffy.Assert` | Expect style — `import Fluffy.Expect` |
| --- | --- |
| `assert(visible(locator))` | `expect(to_be_visible(locator))` |
| `refute(visible(locator))` | `expect(not_(to_be_visible(locator)))` |
| `assert(page_url("/creatures"))` | `expect(page_to_have_url("/creatures"))` |

Each call above is a step in a `session |> …` pipeline. See
[Assertion styles](docs/assertion-styles.md) for setup and a fuller comparison.

## Migrating from PhoenixTest

The pipeline stays familiar; actions and expectations use composable locators:

| PhoenixTest | Fluffy |
| --- | --- |
| `fill_in("Name", with: "Basilisk")` | `fill(by_label("Name", exact: true), "Basilisk")` |
| `click_button("Register")` | `click(by_role(:button, name: "Register"))` |
| `assert_path("/creatures")` | `assert(page_url(path: "/creatures"))` |

See [Migrating from PhoenixTest](docs/migration-from-phoenix-test.md) for the
full translation table and behavior differences.

Even `:phoenix` checks structural visibility. See
[Visibility and DOM presence](docs/usage.md#visibility-and-dom-presence) before
translating `assert_has` or `refute_has` into visibility assertions.

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
- [Assertion styles](docs/assertion-styles.md) — imported `assert`/`refute` and
  `expect` vocabularies compared
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
