# Fluffy

![A friendly three-headed Fluffy asleep beside an Elixir wizard playing a flute, with the heads labeled Live, Static, and Playwright](https://raw.githubusercontent.com/ftes/fluffy/main/docs/images/fluffy-banner.webp)

**Phoenix feature tests. Three drivers, one Playwright-shaped API.**

[![Hex.pm](https://img.shields.io/hexpm/v/fluffy.svg)](https://hex.pm/packages/fluffy)
[![HexDocs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://fluffy.hexdocs.pm/)
[![CI](https://github.com/ftes/fluffy/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ftes/fluffy/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)

Fluffy tests Phoenix pages and LiveViews directly, or uses a real browser when
needed. Fluffy's behavior is checked against a real browser to verify that tests
run without a browser behave consistently. See the
[capability matrix](docs/capabilities.md) for supported behavior and differences.

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
queries: find Fluffy's row in the "Hagrid's creatures" table and scope both the
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

Follow [Installation and runtime](docs/installation.md) for the dependency,
endpoint, browser, and sandbox configuration.

For the native locator API, establish a lifecycle scope and import its helpers:

```elixir
use ExUnit.Case, async: true
use Fluffy.Test
use Fluffy.Assert

import Fluffy
import Fluffy.Locator
```

Start with `start_session(:phoenix)` for in-process Static and LiveView tests.
Use `start_session(:playwright)` when a test needs a real browser. See
[Installation and runtime](docs/installation.md) for Playwright and Ecto sandbox
setup, then [Usage](docs/usage.md) for writing tests and a shared `FluffyCase`.

## Coming from PhoenixTest

Replace `import PhoenixTest` with `import Fluffy.PhoenixTest` and add
`use Fluffy.Test` to your test modules. Existing pipelines keep familiar helpers
such as `fill_in`, `click_button`, and `assert_has`, and their prepared connections:

```elixir
import Fluffy.PhoenixTest

# Inside a test with Fluffy lifecycle setup:
conn
|> visit("/creatures/new")
|> fill_in("Name", with: "Basilisk")
|> click_button("Register")
|> assert_has("#notice", text: "Creature registered")
|> assert_path("/creatures")
```

The facade makes Fluffy mostly a drop-in replacement for supported tests, including
browser tests. You also get automatic waiting for LiveView actions and assertions,
automatic LiveView connection waiting in browser tests, and LiveView tests that see
the whole page, including the root layout, `live_title` updates, and portal content.

Use the facade import on its own. The [migration guide](docs/migration-from-phoenix-test.md)
shows complete setup, the same helpers with Playwright, and compatibility
boundaries. Adopting the native locator API is optional.

For native tests, choose an [assertion vocabulary](docs/assertions.md):
`use Fluffy.Assert` or `import Fluffy.Expect`.

## Beyond page interactions

Capture downloads, open new tabs, handle dialogs, and observe network events
with Fluffy's event API. Register a wait before an action, then await a value.
Predicates select events; ordinary ExUnit assertions inspect their metadata. See [Events and pages](docs/advanced-events.md)
for examples and the [Capability matrix](docs/capabilities.md) for what each
backend supports.

## Guides

- [Installation and runtime](docs/installation.md) — endpoint, browser, and
  Ecto sandbox setup
- [Usage](docs/usage.md) — your first test, backend choice, and a shared test case
- [Locators and frames](docs/locators.md) — finding elements and reaching into iframes
- [Actions and waiting](docs/actions.md) — actions, waiting, uploads, and controlling time
- [Assertions](docs/assertions.md) — imported `assert`/`refute` and `expect`
  vocabularies compared, visibility, and page assertions
- [Debugging and native access](docs/debugging.md) — failures, browser diagnostics,
  and the native escape hatch
- [Events and pages](docs/advanced-events.md) — tabs, windows, iframe
  limitations, downloads, navigation, dialogs, and network events
- [Coming from PhoenixTest](docs/migration-from-phoenix-test.md) — an alternate
  starting point for existing PhoenixTest suites
- [Upgrading to 0.9](docs/upgrading.md) — what a 0.8 suite must change
- [Capability matrix](docs/capabilities.md) — backend differences and limitations

See [CONTRIBUTING.md](https://github.com/ftes/fluffy/blob/main/CONTRIBUTING.md) for developing Fluffy itself.

## License

Fluffy is released under the [MIT License](LICENSE.md).
