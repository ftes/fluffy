# Debugging and native access

The snippets assume the imports from [Your first test](usage.md#your-first-test) and an initialized `session`.

## Operation failures and browser diagnostics

Element-action failures raise `Fluffy.OperationError` across drivers. Rescue it
uniformly and inspect `backend`, `driver`, `operation`, `locator` (or file-chooser
handle), and `cause` for details. This includes `submit` and file selection, and on
Playwright also `visit`, `reload`, history navigation, clock calls, and the page
handling around an `unwrap` callback, whose own errors pass through.

For Playwright, `cause` is the native PlaywrightEx exception (such as
`PlaywrightEx.TimeoutError`), including its call log. For Phoenix, it retains `Fluffy.StrictnessError` or
`Fluffy.ActionabilityError`, including structural reasons and candidates. LiveView
finishes its action retries before wrapping the final failure. Browser failures
are not classified by parsing messages or inspecting a later DOM snapshot.

Invalid arguments, unsupported capabilities, and unexpected programming errors
are not wrapped in `Fluffy.OperationError`.

Failed assertions remain `ExUnit.AssertionError`. Browser assertion messages
include the expected condition and Playwright's received values, timeout details,
and call log. No candidate markup is reconstructed after browser failure.

Trace a Playwright test with `trace: :on` (or `:retain_on_failure` in the config, see
[Playwright setup](installation.md#playwright-setup)), and name its steps with
`Fluffy.Playwright.step/4`:

```elixir
setup context, do: PlaywrightEx.Test.record_artifacts(context, trace: :on)

test "brews Polyjuice" do
  start_session(:playwright)
  |> visit("/potions/polyjuice")
  |> step("Brew Polyjuice Potion", fn session ->
    session
    |> fill(by_label("Boomslang skin"), "3")
    |> click(by_role(:button, name: "Brew"))
  end)
end
```

The test's one `trace.zip` covers every page of all its sessions; open it with
`mix playwright_ex.cli show-trace test-results/<test>/trace.zip`. Steps nest and link to
their source; they are `PlaywrightEx.Test.step/3`'s, so Phoenix sessions raise
`Fluffy.CapabilityError`.

Save an explicit PNG while retaining the pipeline with:

```elixir
session
|> Playwright.screenshot("tmp/screenshots/polyjuice.png", full_page: true)
|> assert(visible(by_text("Potion ready")))
```

`Fluffy.open_browser/1` opens an HTML snapshot of the active page in your default
browser and returns the session, on every driver. Scripts are removed, and browser
state such as unsaved input values is not captured:

```elixir
session
|> visit("/chamber")
|> open_browser()
```

See [Playwright setup](installation.md#playwright-setup) for console logging,
traces, screenshots and videos. See [Events and pages](advanced-events.md)
for downloads, popups, dialogs, and network events.

## Native escape hatch

Use `Fluffy.unwrap/2` for an uncommon driver-native operation that has no first-class
Fluffy API. It returns the reconciled session, so the pipeline can continue, but the
callback value is intentionally driver-specific:

```elixir
session
|> unwrap(fn %Phoenix.LiveViewTest.View{} = view ->
  Phoenix.LiveViewTest.render_hook(view, "open-chamber", %{"phrase" => "open"})
end)
|> assert(visible(by_text("Chamber opened")))
```

To read a value instead, use `Fluffy.unwrap_and_return/2`. It returns the
callback's result. On LiveView and Playwright pages it reconciles the page like
`Fluffy.unwrap/2`, including redirects the callback causes, so keep using the same
session afterwards; a Static page stays as it is, whatever conn the callback returns:

```elixir
html = unwrap_and_return(session, &Phoenix.LiveViewTest.render/1)
```

The callback receives the current `%Plug.Conn{}` on a Static page, a
`%Phoenix.LiveViewTest.View{}` on a LiveView page, or a
`%PlaywrightEx.Page{}` on a Playwright page.

A Static `Fluffy.unwrap/2` callback must return its updated `Plug.Conn` because
connections are immutable, while a Static `Fluffy.unwrap_and_return/2` callback may
return anything and leaves the conn alone. LiveView and Playwright `Fluffy.unwrap/2`
callback results are ignored: Fluffy retains and reconciles the original View or Page. Exceptions, throws, and exits pass
through unchanged. Prefer PlaywrightEx bang functions inside the callback when
failure should stop the test.

Do not consume `assert_patch` or `assert_redirect` notifications inside a LiveView
callback: Fluffy uses them to reconcile navigation. Assert the resulting page or URL
after `Fluffy.unwrap/2`.

Reach the context and frame with `PlaywrightEx.Page.context/1` and
`PlaywrightEx.Page.main_frame/1`. A document navigated natively, inside or after the
callback, is adopted before the next Fluffy action. Do not close the page or
context natively; use the [event and page APIs](advanced-events.md) for lifecycle
operations and registrations that must precede an action.

`Fluffy.Playwright.unwrap/3` passes the `%PlaywrightEx.Locator{}` for a Fluffy
locator instead, resolved in the active page and through its frame locators, with
the same navigation handling. `Fluffy.Playwright.unwrap_and_return/3` returns the
callback's result instead:

```elixir
session
|> Fluffy.Playwright.unwrap(by_role(:button, name: "Rename"), &PlaywrightEx.Locator.dblclick!/1)
|> assert(visible(by_label("Name")))
```

Event values such as `Fluffy.Response` reach their PlaywrightEx counterpart through
`Fluffy.unwrap_and_return/2`; see [Native values](advanced-events.md#native-values). See
[PlaywrightEx coverage](capabilities.md#playwrightex-coverage) for which native
calls are safe.
