# Usage

Start each test with the Phoenix (`:phoenix`) or Playwright (`:playwright`)
backend. The Phoenix backend automatically selects the Static
(`Phoenix.ConnTest`) or LiveView (`Phoenix.LiveViewTest`) driver for each page
and can transition between them as the user navigates. Use Playwright when the
behavior depends on JavaScript or other browser-owned capabilities.

## Your first test

Import the actions and locators; `use Fluffy.Assert` imports the assertion vocabulary:

```elixir
defmodule MyAppWeb.CreatureTest do
  use ExUnit.Case, async: true
  use Fluffy.Assert

  import Fluffy
  import Fluffy.Locator

  setup context do
    Fluffy.Test.setup(context)
  end

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

Actions and assertions return the updated `Fluffy.Session`, so an ordinary Elixir
pipeline represents the user's journey. The lifecycle established by
`Fluffy.Test.setup/1` closes every session when the test finishes.

The examples describe an illustrative Hogwarts application; routes, controls,
and event handlers must exist in the application under test. Later snippets
assume the same imports and an initialized `session`. Upload examples also
require the named fixture files.

The first example assumes `config :fluffy, endpoint: MyAppWeb.Endpoint` in
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

A Playwright session owns an isolated BrowserContext. Create another session
for another isolated user; pages opened inside one session share that user's
cookies and storage.

See the [capability matrix](capabilities.md) for backend differences.

## Shared test case

Put shared imports and session setup in an application-owned `FluffyCase`.
Keep your ordinary `ConnCase` for fixtures, routes, and sandbox setup, then
start the Fluffy session after it:

```elixir
# test/support/fluffy_case.ex
defmodule MyAppWeb.FluffyCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use MyAppWeb.ConnCase
      use Fluffy.Assert

      import Fluffy
      import Fluffy.Locator

      alias Fluffy.Event

      setup context do
        :ok = Fluffy.Test.setup(context)
        %{session: start_session(Map.get(context, :backend, :phoenix))}
      end
    end
  end
end
```

Tests receive `session` in their context and default to Phoenix. Use
`@moduletag backend: :playwright` for an entire module, `@describetag` for a
describe block, or `@tag` for one test—without a separate browser test module:

```elixir
defmodule MyAppWeb.PotionTest do
  use MyAppWeb.FluffyCase, async: true

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

## Locators

Prefer locators that describe the interface as a user experiences it:

1. Use a label for a form control.
2. Use a role and accessible name for an interactive element.
3. Use text for rendered content, with a visibility assertion when needed.
4. Use a test ID when user-facing names are ambiguous.
5. Use CSS for structure that has no user-facing identity.

```elixir
session
|> fill(by_label("Name"), "Basilisk")
|> click(by_role(:button, name: "Register"))
|> assert(visible(by_text("Creature registered")))
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
locator, or use `assert(count(locator, n))` when multiple matches are
the intended assertion.

## Actions and expectations

Actions and expectations use the same API on both backends:

```elixir
session
|> visit("/creatures/fluffy")
|> fill(by_label("Keeper"), "Rubeus Hagrid")
|> check(by_label("Flute ready"))
|> select_option(by_label("Status"), %{label: "Asleep"})
|> click(by_role(:button, name: "Save creature"))
|> assert(enabled(by_role(:button, name: "Save creature")))
|> assert(disabled(by_label("Species")))
|> assert(value(by_label("Keeper"), "Rubeus Hagrid"))
|> assert(editable(by_label("Keeper")))
|> assert(checked(by_label("Flute ready")))
|> assert(visible(by_text("Creature saved")))
```

Use `checked(locator, checked: false)` for an unchecked control. The
browser-owned indeterminate state is Playwright-only:

```elixir
session
|> assert(checked(by_label("All ingredients"), indeterminate: true))
```

Static and LiveView raise `Fluffy.CapabilityError` for indeterminate state.

LiveView expectations observe fresh renders and retry transient missing or
actionability failures until their deadline. Static expectations are
immediate. Playwright uses the browser's native waiting behavior. Pass
`timeout:` to an action or expectation when a particular operation needs a
different deadline.

### Form submission and keyboard actions

Use `submit(form_locator)` when the intent is native form submission without a
specific submitter. Click the intended submit button when its `name=value` or
override attributes matter. `press(locator, "Enter")` is reserved for the
documented implicit-Enter default action, not as shorthand for `submit`.
The Playwright driver applies native constraint validation; the Static and
LiveView drivers deliberately bypass it and submit the current structural form
state.

LiveView supports declarative Enter, Space, and Tab handlers. Use Playwright
for more complex keyboard behavior; see
[LiveView timing and keyboard events](capabilities.md#liveview-timing-and-keyboard-events).

## Assertions

The examples use `use Fluffy.Assert`, which imports `assert`, `refute`, and
all assertion constructors. Place it after your ExUnit case module to preserve
ordinary ExUnit assertions without import clashes. See
[Assertion styles](assertion-styles.md) for the equivalent `expect` vocabulary,
constructor names, options, and negation semantics.

## Visibility and DOM presence

Even the `:phoenix` backend checks **structural visibility**, rather than just
DOM presence. Its Static and LiveView drivers treat a matched element with a
`hidden` attribute or `aria-hidden="true"` as invisible. This differs from
PhoenixTest's `assert_has` and `refute_has`, which check for matching DOM
elements rather than their visibility.

Phoenix does not compute CSS or browser layout: a CSS class or inline
`display: none` alone does not make an element structurally invisible. Use
`:playwright` to test rendered visibility. Its browser visibility rules also
differ from structural checks: `aria-hidden="true"` alone does not visually
hide an element.

Choose the assertion that expresses the intended behavior:

```elixir
# Require a visible element.
session |> assert(visible(by_css("#notice")))

# Allow the element to be absent or invisible.
session |> refute(visible(by_css("#notice")))

# Require DOM absence, including hidden elements.
session |> assert(count(by_css("#notice"), 0))
```

To require an element to remain in the DOM but be invisible, assert
`count(by_css("#notice"), 1)` before refuting its visibility. Use a CSS locator
for these presence checks; role locators can exclude structurally hidden
elements before the assertion runs.

## Page assertions

Page assertion constructors use a `page_` prefix and target
the active page:

```elixir
session
|> assert(page_title("Chamber of Secrets"))
|> assert(page_title(~r/^Chamber/))
|> refute(page_title("Chamber sealed"))
```

Title assertions normalize whitespace. LiveView and Playwright retry until
the title matches; Static checks immediately. LiveView also observes later
`@page_title` updates.

URL assertions use the same `page_` prefix. Strings and regular expressions
match the complete canonical URL. Use the structured form when query
serialization order is not part of the contract:

```elixir
session
|> assert(page_url(path: "/potions"))
|> assert(
  page_url(
    path: "/potions",
    query: %{"state" => "brewing", "ingredient" => ["lacewing", "boomslang"]},
    query_mode: :subset
  )
)
```

Exact URL strings include the query and fragment; relative strings resolve
against the session base URL. Structured matching can select `:path`, `:query`,
and `:fragment`; omitted components are ignored.

Structured queries decode like `URLSearchParams`: distinct parameter-name
order is ignored, and repeated values retain their order and duplicates.
Exact query mode rejects unrelated names; `query_mode: :subset` allows them
while requiring all values for each requested name.

## Reloading

Use `reload/1` to reload the active document:

```elixir
session
|> visit("/chambers/secrets")
|> assert(visible(by_role(:heading, name: "Chamber of Secrets")))
|> reload()
|> assert(visible(by_role(:heading, name: "Chamber of Secrets")))
|> assert(page_url("/chambers/secrets"))
```

The Phoenix backend dispatches the current URL again and selects the driver for
the returned document. The Playwright backend uses the page's native reload.
`reload/1` promises a fresh document, not preservation of unsaved client-side
state.

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
  bytes: "potion,vials\nPolyjuice Potion,3\n",
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
click. Pass its result key to `set_input_files/3`; see
[Advanced events and pages](advanced-events.md#file-choosers).

## Browser diagnostics

Start a context-wide trace explicitly when debugging a Playwright scenario:

```elixir
alias Fluffy.Playwright

start_session(:playwright)
|> Playwright.trace(open: false)
|> visit("/potions/polyjuice")
|> step("Brew Polyjuice Potion", fn session ->
  session
  |> fill(by_label("Boomslang skin"), "3")
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
|> assert(visible(by_text("Potion ready")))
```

The configured Playwright console logger reports browser console messages and
uncaught page errors without turning them into assertions. Separately,
`artifact_dir` enables best-effort HTML, screenshot, and formatted-error files
when a public browser operation fails. Diagnostic capture never replaces the
original operation error. See [Playwright setup](installation.md#playwright-setup)
for artifact, trace, and logger configuration.

Downloads, popups, navigation metadata, dialogs, and network events require a
listener to be installed before the triggering action. Use the pipeable
`wait_for(Event.*(...))` APIs described in
[Advanced events and pages](advanced-events.md).

## Browser-only evaluation

Use `Fluffy.Playwright.evaluate/2` when a Playwright test needs a value from
the active page:

```elixir
alias Fluffy.Playwright

session
|> then(fn session ->
  data_url = Playwright.evaluate(session, "document.querySelector('canvas').toDataURL()")

  assert data_url =~ "data:image/png"
  session
end)
|> click(by_role(:button, name: "Reveal diary message"))
```

`evaluate/2` returns the JavaScript result, not the session. Use `then/2`, as
above, to continue a pipeline. Function-style expressions can pass
`is_function: true` and `arg:`. Phoenix sessions raise a capability error
because Phoenix does not execute client code.

## Native escape hatch

Use `unwrap/2` for an uncommon driver-native operation that has no first-class
Fluffy API. It returns the reconciled session, so the pipeline can continue,
but the callback value is intentionally driver-specific:

```elixir
session
|> unwrap(fn %Phoenix.LiveViewTest.View{} = view ->
  Phoenix.LiveViewTest.render_hook(view, "open-chamber", %{"phrase" => "open"})
end)
|> assert(visible(by_text("Chamber opened")))
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
