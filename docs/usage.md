# Usage

Start each test with the Phoenix (`:phoenix`) or Playwright (`:playwright`)
backend and keep the rest focused on the user's journey. Most application
tests should run once. The Phoenix backend automatically selects the Static
(`Phoenix.ConnTest`) or LiveView (`Phoenix.LiveViewTest`) driver for each page
and can transition between them as the user navigates. Use Playwright when the
behavior depends on JavaScript or other browser-owned capabilities.

## Your first test

Import the actions, locators, and expectation constructors, and keep session
startup in a small test helper. Always import `Fluffy.Expect`: the enclosing
`expect(...)` call makes an additional `Expect.` prefix redundant.

```elixir
defmodule MyAppWeb.ChamberAccessTest do
  use ExUnit.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Page
  alias Fluffy.Playwright

  setup context do
    Fluffy.Test.setup(context)
  end

  defp start_app_session(backend \\ :phoenix), do: start_session(backend)

  test "opens the Chamber of Secrets" do
    start_app_session()
    |> visit("/chamber")
    |> fill(by_label("Student"), "Hermione Granger")
    |> fill(by_label("Password"), "parseltongue")
    |> click(by_role(:button, name: "Open chamber"))
    |> expect(visible(by_text("The chamber is open")))
    |> expect(Page.to_have_url("/chambers/secrets"))
  end
end
```

Page-specific assertions live on `Fluffy.Page`, which keeps them
discoverable separately from locator expectations:

```elixir
alias Fluffy.Page

session
|> expect(Page.to_have_title("Chamber of Secrets"))
|> expect(Page.to_have_title(~r/^Chamber/))
|> expect(not_(Page.to_have_title("Chamber sealed")))
```

Title expectations follow Playwright's retrying, whitespace-normalized
`toHaveTitle` behavior. On LiveViews they also observe later `@page_title`
updates.

URL expectations use the same page namespace. Strings and regular expressions
match the complete canonical URL. Use the structured form when query
serialization order is not part of the contract:

```elixir
session
|> expect(Page.to_have_url(path: "/potions"))
|> expect(
  Page.to_have_url(
    path: "/potions",
    query: %{"state" => "brewing", "ingredient" => ["lacewing", "boomslang"]},
    query_mode: :subset
  )
)
```

The path-only form ignores query and fragment. Structured queries decode like
`URLSearchParams`: distinct parameter-name order is ignored, repeated values
remain ordered, and subset mode permits unrelated names.

Every operation returns the updated `Fluffy.Session`, so an ordinary Elixir
pipeline represents the user's journey. The lifecycle established by
`Fluffy.Test.setup/1` closes every session when the test finishes.

The example assumes `config :fluffy, endpoint: MyAppWeb.Endpoint` in
`config/test.exs`. Fluffy derives the base URL from the endpoint. Explicit
session options remain available for tests that target another endpoint or
origin.

Every Fluffy test calls `Fluffy.Test.setup/1`, whether or not the
application uses Ecto. When `ecto_repos` are configured, the same callback
also establishes sandbox ownership. See
[Installation and runtime](installation.md#ecto-sandbox) for endpoint and
sandbox configuration.

## Choosing a backend

Use `:phoenix` for the common case: rendered controller pages, forms,
LiveViews, links, redirects, cookies, and LiveView events. Its first visit
selects the Static or LiveView driver. Later document navigations select the
driver for the new page again without changing the public session.

The LiveView driver synchronizes form mutations eagerly: `fill`, `check`,
`uncheck`, and `select_option` immediately dispatch an applicable `phx-change`
and reconcile the server render before returning. It deliberately ignores
`phx-debounce` and `phx-throttle`, as PhoenixTest does. Choose Playwright when
the test is about delayed or blur-only delivery, coalescing, cancellation, or
throttle suppression rather than the resulting application state.

Use `:playwright` when the behavior depends on JavaScript, browser layout,
native-validation events or blocking, dialogs, request/response events, or
another capability shown as unavailable on Phoenix. With the helper above,
the choice is local to the test:

```elixir
test "updates the preview rendered by a JavaScript hook" do
  start_app_session(:playwright)
  |> visit("/creatures/new")
  |> fill(by_label("Name"), "Basilisk")
  |> expect(visible(by_text("Preview: Basilisk")))
end
```

A Playwright session owns an isolated BrowserContext. Create another session
for another isolated user; pages opened inside one session share that user's
cookies and storage.

Application suites run each scenario once. Give it the backend its behavior
requires. Paired Phoenix and Playwright runs belong to Fluffy's internal
conformance suite; they prove the library's portability contract without
duplicating consumer tests.

The full boundary is listed in the [capability matrix](capabilities.md).

## Locators

Prefer locators that describe the interface as a user experiences it:

1. Use a label for a form control.
2. Use a role and accessible name for an interactive element.
3. Use visible text for rendered content.
4. Use a test ID when user-facing names are ambiguous.
5. Use CSS for structure that has no user-facing identity.

```elixir
session
|> fill(by_label("Creature name"), "Basilisk")
|> click(by_role(:button, name: "Register"))
|> expect(visible(by_text("Creature registered")))
```

Locators are values, so they can be scoped and reused:

```elixir
potions = by_css("#potions")
potion = by_role(potions, :row, name: "Polyjuice Potion")

session
|> click(by_role(potion, :button, name: "Inspect"))
```

Available constructors are `by_role`, `by_text`, `by_label`,
`by_placeholder`, `by_alt_text`, `by_title`, `by_test_id`, and `by_css`.
Refine a locator with `filter`, `first`, `last`, or zero-based `nth`.

Single-target actions are strict: if a locator matches more than one element,
Fluffy reports the ambiguity instead of choosing for you. Narrow the
locator, or use `expect(count(locator, n))` when multiple matches are
the intended assertion.

## Actions and expectations

Actions and expectations use the same API on both backends:

```elixir
session
|> visit("/creatures/fluffy")
|> fill(by_label("Keeper"), "Rubeus Hagrid")
|> check(by_label("Flute ready"))
|> select_option(by_label("Status"), "Asleep")
|> click(by_role(:button, name: "Save creature"))
|> expect(enabled(by_role(:button, name: "Save creature")))
|> expect(disabled(by_label("Species")))
|> expect(value(by_label("Keeper"), "Rubeus Hagrid"))
|> expect(editable(by_label("Keeper")))
|> expect(checked(by_label("Flute ready")))
|> expect(visible(by_text("Creature saved")))
```

Use `checked(locator, checked: false)` for an unchecked control. The
browser-owned indeterminate state is Playwright-only:

```elixir
session
|> expect(checked(by_label("All ingredients"), indeterminate: true))
```

Static and LiveView raise `Fluffy.CapabilityError` for indeterminate state
instead of guessing about a DOM property that only application JavaScript can
set.

LiveView expectations observe fresh renders and retry transient missing or
actionability failures until their deadline. Static expectations are
immediate. Playwright uses the browser's native waiting behavior. Pass
`timeout:` to an action or expectation when a particular operation needs a
different deadline.

Use `submit(form_locator)` when the intent is native form submission without a
specific submitter. Click the intended submit button when its `name=value` or
override attributes matter. `press(locator, "Enter")` is reserved for the
documented implicit-Enter default action, not as shorthand for `submit`.
The Playwright driver applies native constraint validation; the Static and
LiveView drivers deliberately bypass it and submit the current structural form
state.

On a LiveView page, the shared `Enter`, `Space`, and `Tab` actions also deliver
plain or `JS.push`-only `phx-keydown`/`phx-keyup` bindings. `phx-key` filtering,
window bindings, `phx-target`, current values, and default-action ordering are
covered by the paired browser corpus. Use Playwright for modified key chords,
repeat or debounce timing, custom LiveSocket metadata, inline listeners, and
bindings that run client-side `JS` commands such as `JS.dispatch`.

## Files and uploads

The same public action covers ordinary multipart forms and the supported
managed LiveView upload lifecycle:

```elixir
session
|> set_input_files(by_label("Evidence"), ["diary-front.pdf", "diary-back.pdf"])
|> click(by_role(:button, name: "Upload"))
```

The path list preserves selection order. Pass `[]` to clear the input. Use a
typed in-memory payload for generated bytes or a remote browser:

```elixir
payload = %Fluffy.FilePayload{
  name: "potion-ledger.csv",
  bytes: "potion,vials\nSleeping Draught,3\n",
  content_type: "text/csv"
}

session
|> set_input_files(by_label("Report"), payload)
|> click(by_role(:button, name: "Upload"))
```

One path or payload, a homogeneous list of either, and `[]` are accepted.
Fluffy validates and snapshots the complete selection before changing the
page. The aggregate default is 10 MB; configure `:file_input_max_bytes` or pass
`max_bytes:` for one action. Error messages and diagnostic artifacts do not
copy payload contents.

Playwright can also capture a script-opened chooser before the triggering
click. Pass its result key to `set_input_files/4`; see
[Advanced events and pages](advanced-events.md#file-choosers).

## Reloading

Use `reload/1` to reload the active document:

```elixir
session
|> visit("/chambers/secrets")
|> expect(visible(by_role(:heading, name: "Chamber of Secrets")))
|> reload()
|> expect(visible(by_role(:heading, name: "Chamber of Secrets")))
|> expect(Page.to_have_url("/chambers/secrets"))
```

The Phoenix backend dispatches the current URL again and selects the driver for
the returned document. The Playwright backend uses the page's native reload.
`reload/1` promises a fresh document, not preservation of unsaved client-side
state.

## Browser-only evaluation

Use `Fluffy.Playwright.evaluate/2` when a Playwright test needs a value from
the active page:

```elixir
session
|> then(fn session ->
  data_url =
    Playwright.evaluate(
      session,
      "document.querySelector('canvas').toDataURL()"
    )

  assert data_url =~ "data:image/png"
  session
end)
|> click(by_role(:button, name: "Reveal diary message"))
```

`evaluate/2` returns the JavaScript result, not the session. Use `then/2`, as
above, to continue a pipeline. Function-style expressions can pass
`is_function: true` and `arg:`. Phoenix sessions raise a capability error
instead of pretending to execute client code.

## Browser diagnostics

Start a context-wide trace explicitly when debugging a Playwright scenario:

```elixir
start_app_session(:playwright)
|> Playwright.trace(open: false)
|> visit("/potions/polyjuice")
|> step("Brew Polyjuice Potion", fn session ->
  session
  |> fill(by_label("Boomslang skin"), "3 measures")
  |> click(by_role(:button, name: "Brew"))
end)
```

Fluffy saves the trace before closing its BrowserContext. A trace covers
the session's main page and captured popups; different sessions produce
different archives. Explicit tracing opens Trace Viewer by default for local
debugging, while `open: false` is appropriate in CI. `step/3` remains portable:
it adds nested, source-linked trace groups when tracing is active and simply
runs the callback on Phoenix or an untraced Playwright session.

Save an explicit PNG while retaining the pipeline with:

```elixir
session
|> Playwright.screenshot("tmp/screenshots/polyjuice.png", full_page: true)
|> expect(visible(by_text("Potion ready")))
```

The configured Playwright console logger reports browser console messages and
uncaught page errors without turning them into assertions. Separately,
`artifact_dir` enables best-effort HTML, screenshot, and formatted-error files
when a public browser operation fails. Diagnostic capture never replaces the
original operation error.

Downloads, popups, navigation metadata, dialogs, and network events require a
listener to be installed before the triggering action. Use the pipeable
`wait_for(Event.*(...))` APIs described in
[Advanced events and pages](advanced-events.md).

## Native escape hatch

Use `unwrap/2` for an uncommon driver-native operation that has no first-class
Fluffy API. It returns the reconciled session, so the pipeline can continue,
but the callback value is intentionally driver-specific:

```elixir
session
|> unwrap(fn %Phoenix.LiveViewTest.View{} = view ->
  Phoenix.LiveViewTest.render_hook(view, "open-chamber", %{"phrase" => "open"})
end)
|> expect(visible(by_text("Chamber opened")))
```

The callback receives the current `%Plug.Conn{}` on a Static page, a
`%Phoenix.LiveViewTest.View{}` on a LiveView page, or a
`%Fluffy.Playwright.Handle{}` on a Playwright page.

A Static callback must return its updated `Plug.Conn` because connections are
immutable. LiveView and Playwright callback results are ignored: Fluffy retains
and reconciles the original View or Handle. Exceptions, throws, and exits pass
through unchanged. Match PlaywrightEx `{:error, reason}` results inside the
callback when failure should stop the test.

The Playwright handle exposes only `context_id`, `page_id`, `frame_id`,
`connection`, and `timeout`. Operations that change owned lifecycle or require
a listener before an action must use Fluffy's first-class APIs. Pre-arm
navigation, pages, downloads, dialogs, requests, and responses with
`wait_for(Event.*(...))`; manage named pages with `switch_page` and
`close_page`. Closing a tracked page/context or creating an untracked page
through `unwrap/2` is unsupported.

Native callbacks do not promise portability between drivers. If an operation is
repeated often—or Fluffy must own its timing, cleanup, or result—it is a good
candidate for a small first-class API.

## One backend per scenario

Choose the backend at session startup and keep the rest of the test focused on
the user journey. Use Phoenix unless the behavior under test depends on a real
browser. In that case, run the scenario with Playwright—not once with each.

Fluffy's own conformance corpus is parameterized across drivers because the
library must prove its shared semantics. That machinery is deliberately not a
consumer testing pattern.
