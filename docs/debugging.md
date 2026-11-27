# Debugging and native access

Start with the failure message. If the sequence of actions matters, open the
test trace. The examples use the setup from [Your first test](usage.md#your-first-test).

## Operation failures and browser diagnostics

**Did the assertion fail?** `ExUnit.AssertionError` tells you which condition
the page missed. On Playwright, read the received values, timeout and call log:
these describe the check when it ran, without reconstructing a later DOM.
On Phoenix, a failed `to_be_visible` assertion tells you whether the locator matched
nothing or matched a hidden element. If a named role locator matched nothing,
look for other accessible names for that role in the locator’s scope.

**Did the action fail?** `Fluffy.OperationError` records the operation, backend,
driver, locator (or file chooser), and underlying `cause`:

- On Playwright, a native exception such as `Playwright.TimeoutError` carries
  the call log. On Phoenix, strictness and actionability errors identify the
  matching candidates or structural reason; `Fluffy.LiveViewError` means the
  view exited. LiveView reports the final failure after its retries. If an action
  finds no match for a named role, check the other accessible names in its scope.
- If a click found its target but the navigation failed, the navigation error
  has `locator: nil`, just as for `visit` or `reload`. Fluffy supplies a reason
  for failures it detects, such as too many redirects or a view that never connected.

The same error wrapper covers file selection, `submit`, browser history and
clock operations, and Playwright page handling around `unwrap`. The callback's
own errors, invalid arguments, unsupported capabilities and programming errors
pass through.

### Replay the failing step

Tag the test to record a trace. Name the sequence you want to find in the viewer:

```elixir
@tag Playwright.Test.use(trace: :on)
test "brews Polyjuice" do
  start_session(:playwright)
  |> visit("/potions/polyjuice")
  |> step("Brew Polyjuice Potion", fn session ->
    session
    |> fill(by_label("Boomslang skin"), "3")
    |> click(button("Brew"))
  end)
  |> assert_has(by_text("Polyjuice Potion is ready"))
end
```

Open `test-results/<test>/error-context.md` for the failure, source and page's
ARIA snapshot. To replay the actions, run
`mix playwright.cli show-trace test-results/<test>/trace.zip`. One trace covers
every page of every session in the test. Steps nest and link to source on all
drivers; a Phoenix-only trace contains steps but no browser pages. To keep
traces only for failures, configure `trace: :retain_on_failure`
([CI](installation.md#ci)).

### Inspect the current page

For a layout problem, capture the rendered browser page. `screenshot/2` returns
the PNG bytes; `path:` also saves them:

```elixir
Fluffy.Playwright.screenshot(session, path: "tmp/screenshots/polyjuice.png", full_page: true)
```

`Fluffy.open_browser/1` opens an HTML snapshot of the active page in your default
browser and returns the session, on every driver. Scripts are removed, and browser
state such as unsaved input values is not captured:

```elixir
session
|> visit("/chamber")
|> open_browser()
```

See [CI](installation.md#ci) to keep traces, screenshots and videos from failures,
or [Troubleshooting](installation.md#troubleshooting) to log browser output. See [Advanced events and pages](advanced-events.md)
for downloads, popups, dialogs, and network events.

## Native escape hatch

When a test needs an operation Fluffy doesn't expose, use `Fluffy.unwrap/2` to
perform it and continue the pipeline. For example, trigger a LiveView hook and
assert on what the student sees:

```elixir
session
|> unwrap(fn %Phoenix.LiveViewTest.View{} = view ->
  Phoenix.LiveViewTest.render_hook(view, "open-chamber", %{"phrase" => "open"})
end)
|> assert_has(by_text("Chamber opened"))
```

To read a native value, use `Fluffy.unwrap_and_return/2`:

```elixir
html = unwrap_and_return(session, &Phoenix.LiveViewTest.render/1)
assert html =~ "Chamber opened"
```

The active driver determines what the callback receives and how to continue:

- **Static:** the callback receives a `%Plug.Conn{}`. Return the updated conn
  from `unwrap` to keep changes. `unwrap_and_return` can return any value and
  leaves the session's conn alone.
- **LiveView:** the callback receives a `%Phoenix.LiveViewTest.View{}`. Both
  helpers reconcile the original view, including redirects. Leave `assert_patch`
  and `assert_redirect` notifications for Fluffy; assert the resulting page or URL
  afterwards.
- **Playwright:** the callback receives a `%Playwright.Page{}`. Both helpers
  keep tracking that page after navigation. Use bang functions when failure
  should stop the test. Callback exceptions, throws and exits propagate on every driver.

Reach the context and frame with `Playwright.Page.context/1` and
`Playwright.Page.main_frame/1`. Fluffy adopts a natively navigated document
before the next action. Do not close the page or
context natively; use the [event and page APIs](advanced-events.md) for lifecycle
operations and registrations that must precede an action. To act on a page you got
natively, pass it to `Fluffy.Playwright.page/2`, then `Fluffy.Playwright.switch_page/2`.

`Fluffy.Playwright.unwrap/3` passes the `%Playwright.Locator{}` for a Fluffy
locator instead, resolved in the active page and through its frame locators, with
the same navigation handling. `Fluffy.Playwright.unwrap_and_return/3` returns the
callback's result instead:

```elixir
html = Fluffy.Playwright.unwrap_and_return(session, by_css("#prophecy"), &Playwright.Locator.inner_html!/1)
assert html =~ "<em>Lumos</em>"
```

A `Fluffy.Download` and `Fluffy.FileChooser` keep their Playwright counterpart private;
`Fluffy.unwrap_and_return/2` on them reaches it for members Fluffy does not wrap. Other
events and route handlers get Playwright's values themselves. Phoenix downloads have none
and raise `Fluffy.CapabilityError`. See
[Playwright coverage](capabilities.md#playwright-coverage) for which native
calls are safe.
