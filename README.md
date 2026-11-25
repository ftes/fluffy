# Fluffy

![A friendly three-headed Fluffy asleep beside an Elixir wizard playing a flute, with the heads labeled Live, Static, and Playwright](https://raw.githubusercontent.com/ftes/fluffy/main/docs/images/fluffy-banner.webp)

**Phoenix feature tests. Three drivers, one Playwright-shaped API.**

[![Hex.pm](https://img.shields.io/hexpm/v/fluffy.svg)](https://hex.pm/packages/fluffy)
[![HexDocs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://fluffy.hexdocs.pm/)
[![CI](https://github.com/ftes/fluffy/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ftes/fluffy/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)

Feature tests should run without a browser where they can and in one where they
must, and behave the same either way. Fluffy runs Phoenix pages and LiveViews
in-process with `start_session(:phoenix)`, or in a real browser through Playwright
with `start_session(:playwright)`. You pick the backend for each test; Fluffy's
in-process drivers are checked against the browser. See [Why Fluffy](docs/why-fluffy.md)
and the [capability matrix](docs/capabilities.md) for what needs a browser.

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

Add `use Playwright.Test` after your `ConnCase` (or `use ExUnit.Case`), then import the
native locator API's helpers:

```elixir
use MyAppWeb.ConnCase, async: true
use Playwright.Test
use Fluffy.Assert

import Fluffy
import Fluffy.Locator
```

Start with `start_session(:phoenix)` for in-process Static and LiveView tests.
Use `start_session(:playwright)` when a test needs a real browser. See
[Installation and runtime](docs/installation.md) for Playwright and Ecto sandbox
setup, then [Usage](docs/usage.md) for writing tests and starting a session per test.

## Coming from PhoenixTest

Rewrite tests on the native API above. The [migration guide](docs/migration-from-phoenix-test.md)
maps PhoenixTest's common helpers to native steps, and PhoenixTest.Playwright's extras to
native calls. You also get automatic waiting for LiveView actions and assertions,
automatic LiveView connection waiting in browser tests, and LiveView tests that see
the whole page, including the root layout, `live_title` updates, and portal content.

For a plain PhoenixTest suite, or as a temporary step, the `Fluffy.PhoenixTest` facade
keeps familiar helpers such as `fill_in`, `click_button`, and `assert_has`, and their
prepared connections. Replace `import PhoenixTest` with `import Fluffy.PhoenixTest`, after
`use Playwright.Test`:

```elixir
use Playwright.Test
import Fluffy.PhoenixTest

# In a test, with the ConnCase's conn:
conn
|> visit("/creatures/new")
|> fill_in("Name", with: "Basilisk")
|> click_button("Register")
|> assert_has("#notice", text: "Creature registered")
|> assert_path("/creatures")
```

Use the facade import on its own. Once a suite needs `unwrap` for more than a few
calls, rewrite it on the native API rather than mix the two styles.

For native tests, choose an [assertion vocabulary](docs/assertions.md):
`use Fluffy.Assert` or `import Fluffy.Expect`.

## Beyond page interactions

Capture downloads, open new tabs, handle dialogs, and observe network events
with Fluffy's event API. Register a wait before an action, then await a value.
Predicates select events; ordinary ExUnit assertions inspect their metadata. See [Advanced events and pages](docs/advanced-events.md)
for examples and the [Capability matrix](docs/capabilities.md) for what each
backend supports.

## Guides

- [Why Fluffy](docs/why-fluffy.md) — the problem it solves, how it compares with
  PhoenixTest and PhoenixTest.Playwright, and its trade-offs
- [Installation and runtime](docs/installation.md) — endpoint, browser,
  Ecto sandbox setup, and usage rules for coding agents
- [Usage](docs/usage.md) — your first test, backend choice, and a shared test case
- [Locators and frames](docs/locators.md) — finding elements and reaching into iframes
- [Actions and waiting](docs/actions.md) — actions, waiting, uploads, and controlling time
- [Assertions](docs/assertions.md) — imported `assert`/`refute` and `expect`
  vocabularies compared, visibility, and page assertions
- [Debugging and native access](docs/debugging.md) — failures, browser diagnostics,
  and the native escape hatch
- [Advanced events and pages](docs/advanced-events.md) — tabs, windows, iframe
  limitations, downloads, navigation, dialogs, and network events
- [Coming from PhoenixTest](docs/migration-from-phoenix-test.md) — moving PhoenixTest
  and PhoenixTest.Playwright suites to Fluffy
- [Upgrading to 0.9](docs/upgrading.md) — what a 0.8 suite must change
- [Capability matrix](docs/capabilities.md) — backend differences and limitations

See [CONTRIBUTING.md](https://github.com/ftes/fluffy/blob/main/CONTRIBUTING.md) for developing Fluffy itself.

## License

Fluffy is released under the [MIT License](LICENSE.md).
