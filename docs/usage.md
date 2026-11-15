# Usage

Start each test with the Phoenix (`:phoenix`) or Playwright (`:playwright`)
backend. The Phoenix backend automatically selects the Static
(`Phoenix.ConnTest`) or LiveView (`Phoenix.LiveViewTest`) driver for each page
and can transition between them as the user navigates. Use Playwright when the
behavior depends on JavaScript or other browser-owned capabilities.

## Your first test

Add `use Fluffy.Case` after `use ExUnit.Case` (or your `ConnCase`, see
[Shared test case](#shared-test-case)), then import the actions and locators;
`use Fluffy.Assert` imports the assertion vocabulary:

```elixir
defmodule MyAppWeb.CreatureTest do
  use ExUnit.Case, async: true
  use Fluffy.Case
  use Fluffy.Assert

  import Fluffy
  import Fluffy.Locator

  test "puts Fluffy to sleep" do
    start_session(:phoenix)
    |> visit("/creatures/fluffy")
    |> fill(by_label("Keeper"), "Rubeus Hagrid")
    |> click(by_role(:button, name: "Play flute"))
    |> assert(visible(by_text("Asleep")))
    |> assert(page_url("/creatures/fluffy"))
  end
end
```

For tests using browser-only helpers, also `import Fluffy.Playwright`. This
lets you call `new_page`, `current_page`, `pages`, `switch_page`, `close_page`,
`go_back`, `go_forward`, `hover`, `drag_to`, `press_sequentially`, `dblclick`,
and the other browser actions without module qualifiers:

```elixir
import Fluffy
import Fluffy.Locator
import Fluffy.Playwright

start_session(:playwright)
|> visit("/creatures/fluffy")
|> press_sequentially(by_label("Keeper"), "Hagrid", delay: 20)
```

Actions and assertions return a `Fluffy.Session` handle for pipelines. Evolving
state belongs to the session runtime: existing handles see action results even
when the returned handle is discarded. Use each session sequentially from its
owning test process; concurrent use of the same session is unsupported.

For page selection, handle lifetime, and user isolation, see
[Pages, popups, and frames](advanced-events.md#pages-popups-and-frames).

The examples describe an illustrative Hogwarts application; routes, controls,
and event handlers must exist in the application under test.

Complete [Installation and runtime](installation.md) before running these
examples. That guide owns endpoint, browser, and lifecycle/sandbox configuration.
For PhoenixTest-style helpers, follow [Coming from PhoenixTest](migration-from-phoenix-test.md).

## Choosing a backend

Use `:phoenix` for the common case: rendered controller pages, forms,
LiveViews, links, redirects, cookies, and LiveView events. Its first visit
selects the Static or LiveView driver. Later document navigations select the
driver for the new page again without changing the public session.

The LiveView driver sees the whole page, as a browser does: the root layout
around the LiveView, `live_title` updates, and portal content in its target.
`Phoenix.LiveViewTest.render/1` covers only the LiveView's own markup. See
[LiveView document and patch boundaries](capabilities.md#liveview-document-and-patch-boundaries).

For LiveView event scheduling and keyboard limitations, see
[LiveView timing and keyboard events](capabilities.md#liveview-timing-and-keyboard-events).

Use `:playwright` when the behavior depends on JavaScript, browser layout,
native-validation events or blocking, dialogs, request/response events, or
another capability shown as unavailable on Phoenix. Choose the backend when
starting the session:

```elixir
test "updates the preview rendered by a JavaScript hook" do
  start_session(:playwright)
  |> visit("/creatures/new")
  |> fill(by_label("Name"), "Basilisk")
  |> assert(visible(by_text("Preview: Basilisk")))
end
```

See the [capability matrix](capabilities.md) for backend differences.

## Shared test case

`use Fluffy.Case` registers the test, for Phoenix and Playwright sessions alike; the
imports and sessions are yours. Keep the `ConnCase` for fixtures, routes and the sandbox,
and use it first: used after `Fluffy.Case`, its `use ExUnit.Case` imports `test` again
and the module fails to compile on an ambiguous `test/3`.

A setup can start a session per test, here Phoenix by default and the backend of a
`backend` tag otherwise. The tag is the setup's own, so name it as you like. Use
`@moduletag backend: :playwright` for an entire module, `@describetag` for a
describe block, or `@tag` for one test—without a separate browser test module:

```elixir
defmodule MyAppWeb.PotionTest do
  use MyAppWeb.ConnCase, async: true
  use Fluffy.Case
  use Fluffy.Assert

  import Fluffy
  import Fluffy.Locator

  setup context do
    %{session: start_session(context[:backend] || :phoenix)}
  end

  test "lists the available potions", %{session: session} do
    session
    |> visit("/potions")
    |> assert(visible(by_text("Polyjuice Potion")))
  end

  @tag backend: :playwright
  test "brews a potion through a JavaScript hook", %{session: session} do
    session
    |> visit("/potions")
    |> click(by_role(:button, name: "Brew potion"))
    |> assert(visible(by_text("Potion brewed")))
  end
end
```

To share this across modules, put `use Fluffy.Case` in your own case template's
`using`, with the imports and the session setup after it there; the template's own
`setup`, here the sandbox owner's, runs before them:

```elixir
defmodule MyAppWeb.FeatureCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Fluffy.Case
      use Fluffy.Assert

      import Fluffy
      import Fluffy.Locator

      setup context do
        %{session: start_session(context[:backend] || :phoenix)}
      end
    end
  end

  setup tags do
    MyApp.DataCase.setup_sandbox(tags)
    :ok
  end
end
```

When the template's own `setup` starts the session, also put `use Fluffy.Case` right after
`use ExUnit.CaseTemplate`. A template's own `setup` callbacks run before those its `using`
brings in, so the test is then registered before them (a Playwright session started before
the registration makes it raise). The line in `using` stays, as it brings the `test` macro
to each module; there it registers nothing again:

```elixir
defmodule MyAppWeb.FeatureCase do
  use ExUnit.CaseTemplate
  use Fluffy.Case

  using do
    quote do
      use Fluffy.Case
      use Fluffy.Assert

      import Fluffy
      import Fluffy.Locator
    end
  end

  setup tags do
    MyApp.DataCase.setup_sandbox(tags)
    %{session: Fluffy.start_session(tags[:backend] || :phoenix)}
  end
end
```
