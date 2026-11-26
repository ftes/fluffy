# Usage

Start each test with the Phoenix (`:phoenix`) or Playwright (`:playwright`)
backend. The Phoenix backend automatically selects the Static
(`Phoenix.ConnTest`) or LiveView (`Phoenix.LiveViewTest`) driver for each page
and can transition between them as the user navigates. Use Playwright when the
behavior depends on JavaScript or other browser-owned capabilities.

## Your first test

Add `use Playwright.Test` after `use ExUnit.Case` (or your `ConnCase`, see
[Shared test case](#shared-test-case)), then import the actions and locators;
`use Fluffy.Assert`, after `use Playwright.Test`, imports the assertion vocabulary:

```elixir
defmodule MyAppWeb.CreatureTest do
  use ExUnit.Case, async: true
  use Playwright.Test
  use Fluffy.Assert

  import Fluffy
  import Fluffy.Locator

  test "puts Fluffy to sleep" do
    start_session(:phoenix)
    |> visit("/creatures/fluffy")
    |> fill(by_label("Keeper"), "Rubeus Hagrid")
    |> click(by_role(:button, name: "Play flute"))
    |> assert_has(by_text("Asleep"))
    |> assert(page_url("/creatures/fluffy"))
  end
end
```

`import Fluffy.Locator.Roles` adds the shorthands `button("Play flute")` and `link("Owlery")`
for `by_role(:button, name: "Play flute")` and `by_role(:link, name: "Owlery")`
([Button and link shorthands](locators.md#button-and-link-shorthands)).

For tests using Playwright-only helpers, also `import Fluffy.Playwright`. This
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
  |> assert_has(by_text("Preview: Basilisk"))
end
```

See the [capability matrix](capabilities.md) for backend differences.

## Shared test case

`use Playwright.Test` registers the test, which every session, Phoenix or Playwright,
needs: one started outside a registered test raises. The imports and sessions are yours.
Keep the `ConnCase` for fixtures, routes and the sandbox, and use it first: used after
`use Playwright.Test`, its `use ExUnit.Case` imports `test` again and the module fails to
compile on an ambiguous `test/3`. Its options, such as `trace: :on` or context options
like `locale:`, are for the module; tag a describe block or a test with
`Playwright.Test.use/1`, such as `@tag Playwright.Test.use(trace: :on)` (see
`Playwright.Test`).

A setup can start a session per test, here Phoenix by default and the backend of a
`backend` tag otherwise. The tag is the setup's own, so name it as you like. Use
`@moduletag backend: :playwright` for an entire module, `@describetag` for a
describe block, or `@tag` for one test—without a separate browser test module:

```elixir
defmodule MyAppWeb.PotionTest do
  use MyAppWeb.ConnCase, async: true
  use Playwright.Test
  use Fluffy.Assert

  import Fluffy
  import Fluffy.Locator

  setup context do
    %{session: start_session(context[:backend] || :phoenix)}
  end

  test "lists the available potions", %{session: session} do
    session
    |> visit("/potions")
    |> assert_has(by_text("Polyjuice Potion"))
  end

  @tag backend: :playwright
  test "brews a potion through a JavaScript hook", %{session: session} do
    session
    |> visit("/potions")
    |> click(by_role(:button, name: "Brew potion"))
    |> assert_has(by_text("Potion brewed"))
  end
end
```

To share this across modules, put `use Playwright.Test` in your own case template's
`using`, with the imports and the session setup after it there; the template's own
`setup`, here the sandbox owner's, runs before them. It forwards the module's options, so
`use MyAppWeb.FeatureCase, async: true, trace: :on` works:

```elixir
defmodule MyAppWeb.FeatureCase do
  use ExUnit.CaseTemplate

  using opts do
    quote do
      use Playwright.Test, unquote(opts)
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

A template that brings your `ConnCase` in its `using` instead, for the sandbox and fixtures,
forwards the options to both: `use MyAppWeb.ConnCase, unquote(opts)`, then
`use Playwright.Test, unquote(opts)`. `ExUnit.CaseTemplate` passes `use ExUnit.Case` only its
own keys (`async`, `group`, `parameterize`), and `use Playwright.Test` ignores those, so a
`trace: :on` that only reaches the `ConnCase` is dropped without a warning.

When the template's own `setup` starts the session, also put `use Playwright.Test` right after
`use ExUnit.CaseTemplate`. A template's own `setup` callbacks run before those its `using`
brings in, so the test is then registered before them (a Playwright session started before
the registration makes it raise). The line in `using` stays, as it brings the `test` macro
to each module and takes the options; Playwright.Test registers the test once. The one in the body
takes none:

```elixir
defmodule MyAppWeb.FeatureCase do
  use ExUnit.CaseTemplate
  use Playwright.Test

  using opts do
    quote do
      use Playwright.Test, unquote(opts)
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

## Logging in

To start a test logged in without the login form, add a session cookie holding the session
values your login sets, with `Fluffy.add_session_cookie/3`. It signs the endpoint's session
cookie in-process, on both backends:

```elixir
test "Hermione opens her vault" do
  token = Wizards.generate_wizard_session_token(wizard_fixture(name: "Hermione"))

  start_session(:playwright)
  |> add_session_cookie(%{"wizard_token" => token})
  |> visit("/gringotts/vault")
  |> assert_has(by_text("Vault 687"))
end
```

It signs with the endpoint's `Plug.Session` options, which Fluffy reads from the endpoint's
`session_options/0`. Add that one line to `MyAppWeb.Endpoint`, next to its
`@session_options`, or pass `session_options:` to `add_session_cookie/3`:

```elixir
def session_options, do: @session_options
```

The cookie replaces the session's current one, as a fresh login does. When the login does
more than set session keys, such as a remember-me cookie, run your app's own test helper,
such as phx.gen.auth's `log_in_user/2` in `ConnCase`, and one request through the endpoint,
then add the cookies it writes:

```elixir
defp log_in(session, wizard) do
  conn = build_conn() |> log_in_user(wizard) |> get(~p"/")

  cookies =
    for {name, %{value: value}} <- conn.resp_cookies,
        do: %{name: name, value: value, url: Fluffy.base_url(session)}

  Fluffy.add_cookies(session, cookies)
end
```

Cookies added before `visit/2` go with the first request, as in a browser. A Phoenix-only
alternative is `start_session(:phoenix, conn: log_in_user(build_conn(), wizard))`: the
prepared conn's test session goes with the first request.

## Accessibility testing

Follow PlaywrightEx's
[Accessibility testing](https://hexdocs.pm/playwright_ex/testing-with-exunit.html#accessibility-testing)
recipe on a Playwright session, with `Fluffy.Playwright.add_script_tag/2` and
`Fluffy.Playwright.evaluate/2` in place of its `Page` calls:

```elixir
results =
  session
  |> visit("/owlery")
  |> Fluffy.Playwright.add_script_tag(path: axe_path)
  |> Fluffy.Playwright.evaluate("() => axe.run()")

assert results["violations"] == []
```
