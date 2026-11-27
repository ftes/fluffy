# Usage

After [installation](installation.md), start a session, visit a page, and interact
with it through locators. The same test can run in-process or in a browser.

## Your first test

Use your `ConnCase` or `DataCase` to start the [Ecto sandbox owner](installation.md#ecto-sandbox)
before `Playwright.Test` registers the test. Without a sandbox, `ExUnit.Case`
also works. Put `Fluffy.Assert` last.

```elixir
defmodule MyAppWeb.CreatureTest do
  use MyAppWeb.ConnCase, async: true
  use Playwright.Test
  use Fluffy.Assert

  import Fluffy
  import Fluffy.Locator
  import Fluffy.Locator.Roles

  test "puts Fluffy to sleep" do
    start_session(:phoenix)
    |> visit("/creatures/fluffy")
    |> fill(by_label("Keeper"), "Rubeus Hagrid")
    |> click(button("Play flute"))
    |> assert_has(by_text("Asleep"))
    |> assert(page_path("/creatures/fluffy"))
  end
end
```

`import Fluffy.Locator.Roles` adds [role shorthands](locators.md#role-shorthands) such as
`button("Play flute")`, `link("Owlery")`, and `heading("Potions", level: 2)`.

For browser-only actions, also `import Fluffy.Playwright`.
Actions and assertions return a `Fluffy.Session` for the next pipeline step. Existing
handles see the latest page even if you discard a return value. Use each session
sequentially from its owning test process.

For page selection, handle lifetime, and user isolation, see
[Pages, popups, and frames](advanced-events.md#pages-popups-and-frames).

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

Use your `ConnCase` first for fixtures, routes and the sandbox. Then `use Playwright.Test`
registers the test for either backend; reversing the order makes `test/3` ambiguous.
Configure Playwright per test with `@tag Playwright.Test.use(trace: :on)`.

The case below starts a Phoenix session by default. Its setup reads `backend` from the
test context, so `@tag backend: :playwright` selects a browser for one test. Use
`@describetag` or `@moduletag` to apply the same choice more widely.

```elixir
defmodule MyAppWeb.FeatureCase do
  use ExUnit.CaseTemplate

  using opts do
    quote do
      use Playwright.Test, unquote(opts)
      use Fluffy.Assert

      import Fluffy
      import Fluffy.Locator
      import Fluffy.Locator.Roles

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

If `using` also brings in your `ConnCase`, forward `unquote(opts)` to both it and
`Playwright.Test`; Playwright options such as `trace:` are otherwise dropped.

If the template's **own** `setup` starts the session, also add a bare `use Playwright.Test`
right after `use ExUnit.CaseTemplate`. That setup runs before callbacks from `using`
and needs the test registered already. Keep the line in `using` for the test macro
and module options.

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
[Accessibility testing](https://hexdocs.pm/playwright_ex/1.65.0-rc.6/testing-with-exunit.html#accessibility-testing)
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
