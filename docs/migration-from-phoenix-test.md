# Migrating from PhoenixTest

Fluffy is not a compatibility wrapper. It keeps PhoenixTest's successful
in-process session/process/retry shape but uses Playwright behavior for public
matching, actions, forms, and event orchestration.

The migration goal is one recognizable test using the appropriate backend,
not duplicated scenarios. Preserve what the test proves, then choose its
backend.

## Migration workflow and backend choice

Choose `:phoenix` or `:playwright` when starting a session. Do not select the
Static or LiveView driver directly: the Phoenix backend chooses one for each
page and can move Static → LiveView → Static without replacing the session.
Static uses `Phoenix.ConnTest`; LiveView uses `Phoenix.LiveViewTest`. A Playwright
session is one BrowserContext and may contain multiple named pages.

Preserve the source test's backend during migration:

- a PhoenixTest test becomes one Fluffy `:phoenix` test;
- a PhoenixTestPlaywright test becomes one Fluffy `:playwright` test;
- a direct `Phoenix.ConnTest` or `Phoenix.LiveViewTest` contract is not a
  PhoenixTest migration candidate merely because Fluffy is available.

Do not turn consumer tests into Phoenix/Playwright loops. Paired runs belong
to Fluffy's conformance suite, where a portable behavior is reduced to one
small owned fixture. A consumer scenario runs once with its natural backend.

For a large suite, migrate incrementally. Run the original exact test first,
rewrite it in place, and run only that case or small module again. Preserve its
assertions and backend. If it exposes a Fluffy defect, add a focused paired
library regression rather than changing the consumer test to whichever backend
happens to pass.

Inventory both PhoenixTest-specific case modules and tests that directly
`import PhoenixTest`; a case-module-only search can miss substantial coverage.

## Test-module setup

Remove only the PhoenixTest-specific case template. Keep an application's
ordinary ConnCase/DataCase when it provides fixtures, routes, or an existing
sandbox checkout. Add one Fluffy scope to every migrated test module:

```elixir
defmodule MyAppWeb.PotionTest do
  use MyAppWeb.ConnCase, async: true

  import Fluffy
  import Fluffy.Locator
  import Fluffy.Expect

  alias Fluffy.Event
  alias Fluffy.Page

  setup context do
    Fluffy.Test.setup(context)
  end

  defp start_app_session(backend) do
    start_session(backend)
  end
end
```

Configure the endpoint once in `config/test.exs`; configure repositories when
the application uses the Ecto sandbox:

```elixir
config :fluffy,
  endpoint: MyAppWeb.Endpoint,
  ecto_repos: [MyApp.Repo]
```

`Fluffy.Test.setup/1` owns every session created by the test and closes
browser contexts and LiveViews before releasing sandbox ownership. Do not add
per-test `close_session` callbacks. See [Installation and
runtime](installation.md) for Playwright, artifacts, and custom sandbox
transport configuration.

## Name collisions

Expectation constructors are deliberately unqualified inside `expect(...)`;
write `expect(visible(by_text("Potion brewed")))`, not
`expect(Expect.visible(by_text("Potion brewed")))`. Keep event constructors
qualified because their names overlap actions and result accessors.

If the application already imports a conflicting helper, keep the collision
explicit instead of renaming unrelated application code. For example:

```elixir
import Fluffy.Expect, except: [count: 2]
alias Fluffy.Expect

session
|> expect(Expect.count(by_role(:row), 3))
```

## Common rewrites

These translations are good starting points, not permission to preserve
PhoenixTest matching differences:

| PhoenixTest | Fluffy |
| --- | --- |
| `visit("/potions")` | `visit("/potions")` after `start_session/2` |
| `fill_in("Potion name", with: name)` | `fill(by_label("Potion name", exact: true), name)` |
| `select("Boomslang skin", from: "Ingredient")` | `select_option(by_label("Ingredient", exact: true), %{label: "Boomslang skin"})` |
| `check("Ready to brew")` | `check(by_label("Ready to brew", exact: true))` |
| `uncheck("Ready to brew")` | `uncheck(by_label("Ready to brew", exact: true))` |
| `click_button("Brew potion")` | `click(by_role(:button, name: "Brew potion"))` |
| `click_link("Potions")` | `click(by_role(:link, name: "Potions"))` |
| `assert_has("#notice")` | `expect(visible(by_css("#notice")))` |
| `assert_path("/potions")` | `expect(Page.to_have_url(path: "/potions"))` |
| `assert_path("/potions", query_params: params)` | `expect(Page.to_have_url(path: "/potions", query: params))` |
| `assert_has("title", text: "Potions", exact: true)` | `expect(Page.to_have_title("Potions"))` |
| `reload_page()` | `reload()` |
| `upload("Recipe", path)` | `set_input_files(by_label("Recipe", exact: true), path)` |
| `submit()` | `submit(by_css("#potion-form"))` |

Use `%{value: value}`, `%{label: label}`, or `%{index: zero_based_index}` when
the selection criterion must be explicit. One `select_option` call replaces
the selected set; pass a list for a multiple select.

### Exact matching

Do not translate an omitted PhoenixTest `exact:` option mechanically. Its
default depends on the helper, while Fluffy follows Playwright locator
defaults:

| Source operation | PhoenixTest default | Fluffy translation |
| --- | --- | --- |
| `fill_in`, `select`, `check`, `uncheck`, `choose`, and `upload` label lookup | exact | put `exact: true` on `by_label` |
| `select` option text (`exact_option`) | exact | `%{label: text}` already selects an exact option label |
| `assert_has` and `refute_has` text | substring | omit `exact:` or use `exact: false` on the semantic locator |
| `click_button` and `click_link` text | substring | omit `exact:` or use `exact: false` on `by_role` |

Explicit locator exactness maps directly:

```elixir
# PhoenixTest: exact label matching is the implicit default
fill_in("Potion name", with: name)

# Fluffy: preserve that source behavior explicitly
fill(by_label("Potion name", exact: true), name)

# PhoenixTest: intentional partial-label lookup
fill_in("Potion name", with: name, exact: false)

# Fluffy: Playwright already defaults to substring matching
fill(by_label("Potion name"), name)
```

For assertions, put exactness on the locator rather than the expectation:

```elixir
# assert_has("p", text: "Potion brewed", exact: true)
expect(visible(by_text(by_css("p"), "Potion brewed", exact: true)))

# assert_has("p", text: "Potion brewed")
expect(visible(by_text(by_css("p"), "Potion brewed", [])))
```

Preserve a source CSS selector unless changing to accessibility semantics is
intentional. For example, translate `assert_has("td", text: "Potions")` to a
text-filtered `by_css("td")`, not automatically to `by_role(:cell)`. Both may
describe the same element, but the role locator computes accessible names for
every candidate and can be materially more expensive on very large tables.

PhoenixTest's `exact:` on a `value:` or `selected:` assertion applies to its
optional field label, not to the value or selected option itself. Preserve
that distinction by applying `exact:` only to the locator used to find the
field. Page titles are another distinct API: a string passed to
`Page.to_have_title/2` is exact, while a regular expression expresses an
intentional substring or pattern match.

Replace `PhoenixTest.reload_page/1` or
`PhoenixTest.Playwright.reload_page/1` with `Fluffy.reload/1`. Reload is a
session-level operation because it creates a fresh document and may reclassify
a Phoenix page from Static to LiveView or LiveView to Static.

## Playwright events, pages, and independent users

Replace raw event recorders with Fluffy's listener-before-action API. The
listener is installed before the callback runs, and the captured result stays
in the pipe:

```elixir
session
|> wait_for(Event.download(:report), fn session ->
  click(session, by_role(:button, name: "Download potion ledger"))
end)
|> expect(download_suggested_filename(:report, "potions.csv"))
```

Name new pages instead of mutating a Playwright page/frame id manually:

```elixir
session
|> wait_for(Event.popup(:secret_chamber), fn session ->
  click(session, by_role(:link, name: "Open chamber"))
end)
|> switch_page(:secret_chamber)
|> expect(Page.to_have_opener(:main))
|> expect(visible(by_role(:heading, name: "Chamber of Secrets")))
|> close_page()
```

Use the corresponding `Event.dialog`, `Event.navigation`, `Event.request`, or
`Event.response` value for those event types. See [Advanced events and
pages](advanced-events.md) for their result matchers.

One Playwright session is one isolated BrowserContext. For a second browser
identity, start a second session in the same test; the test lifecycle owns
both. Pages inside one session share cookies/storage, while sessions do not.

## Locator differences

- Use typed locators such as `by_role` and `by_label`, then compose them.
  There is no mutable `within` scope.
- Single-target actions follow Playwright strictness. Multiple matches are not
  silently selected; use `nth`/`first` or narrow the locator.
- Matching uses Playwright normalization, accessible-name precedence, and
  zero-based `nth` indexing.
- `aria-labelledby` outranks `aria-label`, which outranks a native label for
  role names. Playwright's label locator matches each `aria-labelledby`
  reference separately.
- Raw CSS must be valid browser CSS. Fluffy does not reinterpret an ID such
  as `#id?`; escape it or prefer a semantic/test-id locator.
- Regex URL expectations evaluate Elixir regular expressions against the
  complete canonical URL on every driver. Wildcard paths and full
  serialized-HTML assertions are not part of the initial release surface.

Translate `within` into immutable locator composition. This avoids hidden
mutable scope and lets the same locator be reused:

```elixir
potion = by_css("#polyjuice-potion")

session
|> fill(by_label(potion, "Brewer"), "Hermione Granger")
|> click(by_role(potion, :button, name: "Brew"))
```

PhoenixTest's positive `at:` positions are one-based; Fluffy follows
Playwright's zero-based indexing:

```elixir
# PhoenixTest: assert_has(".creature", at: 1)
expect(session, visible(nth(by_css(".creature"), 0)))
```

Do not assume `click_link` always becomes `by_role(:link)`. Explicit ARIA
roles win: `<a role="menuitem">Edit</a>` is located as a `:menuitem`. In a
browser test, first perform the interaction that makes a JavaScript-owned menu
visible. In a Phoenix test, a structurally actionable `href`, `phx-click`, or
submit control can be targeted directly when opening the menu is purely
client-side presentation.

## Assertion intent

Choose whether the old assertion meant DOM absence or user-visible state:

```elixir
# The node must not exist.
session |> expect(count(by_css("#flash"), 0))

# The node may exist but must not be visible.
session |> expect(not_(visible(by_css("#flash"))))
```

These are deliberately different. `not_(visible(...))` follows Playwright
visibility; `count(..., 0)` asserts absence. Prefer semantic locators and use
`filter(has_text: ...)` when migrating a selector-plus-text assertion:

```elixir
notice = by_css("#notice") |> filter(has_text: "Potion brewed")
session |> expect(visible(notice))
```

Page title is not an element-title locator. Migrate PhoenixTest's special
`"title"` assertion through the page API:

```elixir
session
|> expect(Page.to_have_title("Potions classroom"))
|> expect(Page.to_have_title(~r/^Potions/))
```

A string is an exact Playwright-style title expectation. PhoenixTest's
default title assertion used substring matching, so translate an intentional
substring check to a regular expression rather than silently strengthening
it; use `Regex.escape/1` when constructing that expression from data.

## Form differences

Fluffy does not keep an “active form” map. `fill`, `check`, `uncheck`, and
`select_option` mutate ordered client properties. Every LiveView change and
final submission is rebuilt from the latest DOM in tree order.

Like PhoenixTest, Fluffy's LiveView driver sends an applicable `phx-change`
immediately after each mutation. `phx-debounce` and `phx-throttle` do not alter
that fast-test synchronization. Keep tests of the eventual application state
on Phoenix; migrate tests of actual debounce/throttle timing to Playwright.

Consequences that intentionally differ from historical PhoenixTest behavior:

- controls removed or disabled after editing are omitted; newly inserted or
  renamed controls use their final ownership/name;
- duplicate names remain ordered entries instead of being prematurely deep
  merged;
- each multiple-select action replaces the selected set, matching
  Playwright's `selectOption`;
- hidden inputs and checkbox entries remain independent successful controls;
- only the activated submitter contributes its value and overrides;
- readonly controls submit, but a user cannot fill them;
- option matching is exact and option fallback values use normalized text;
- invalid input types use the browser's text state;
- specialized scalar input values are retained as supplied strings in Static
  and LiveView; browser sanitization, browser defaults, and type validation
  remain Playwright behavior;
- native-validation events/blocking, image coordinates, directionality, hard
  wrapping, form-associated custom elements, and JavaScript-mutated `FormData`
  are explicit boundaries; Static and LiveView bypass validation and submit
  structurally, while typed local-path and in-memory multipart selection is
  available under the supported file-upload contract.

### Explicit forms and submitters

PhoenixTest's active-form state does not carry over. Target the form when the
test means generic submission:

```elixir
session
|> fill(by_label("Potion name"), "Polyjuice Potion")
|> submit(by_css("#potion-form"))
```

Click the intended submitter when its `name=value`, `formaction`, `formmethod`,
or other submitter override matters:

```elixir
session
|> click(by_role(:button, name: "Save recipe"))
```

Do not use `press(..., "Enter")` as prettier spelling for `submit/2`.
`press/3` represents the browser's proven implicit-Enter default action; it
may select a default submitter or decline to submit. Declarative key handlers
using plain event names or push-only LiveView `JS` are portable for the shared
Enter, Space, and Tab keys. Modified/repeated keys, LiveSocket metadata,
client-side `JS` commands, and general JavaScript keyboard behavior remain a
browser boundary.

### Files and uploads

The same public action covers ordinary multipart forms and managed LiveView
uploads:

```elixir
session
|> set_input_files(by_label("Evidence"), ["diary-front.pdf", "diary-back.pdf"])
|> click(by_role(:button, name: "Upload"))
```

The path list preserves selection order. Pass `[]` to clear the input.
Generated files use `%Fluffy.FilePayload{name:, bytes:, content_type:}`;
Fluffy intentionally accepts no legacy map alias. A Playwright test whose
application JavaScript opens a chooser uses listener-before-action capture:

```elixir
session
|> wait_for(Event.file_chooser(:diary), fn session ->
  click(session, by_role(:button, name: "Choose diary"))
end)
|> set_input_files(:diary, %Fluffy.FilePayload{
  name: "tom-riddles-diary.pdf",
  bytes: pdf_bytes,
  content_type: "application/pdf"
})
```

Keep chooser tests on Playwright. An ordinary PhoenixTest `upload/3` migrates
to the locator form in the table above and can stay with `:phoenix`.

## Navigation, retries, and JavaScript

`expect(Page.to_have_url(...))` compares an exact canonical absolute URL, a
regular expression over that complete URL, or selected structured components.
Root-relative exact strings are resolved against `base_url`. LiveView expectations
retry fresh renders under one deadline and wake on redirects/process exits.
LiveView actions also resolve afresh while a target is
absent, disabled, structurally hidden for a click, readonly for a fill, or
missing the requested select option. Multiple matches and semantically wrong
control types still fail immediately, and Static actions remain immediate.
At expiry Fluffy raises the latest original strictness or actionability error
rather than replacing it with a generic timeout.

PhoenixTest's `assert_path(path)` compares only `URI.path`; it ignores an
existing query unless the source assertion supplies `query_params:`. A
Fluffy string URL expectation is deliberately stricter and compares the
complete canonical URL. Preserve the source assertion's intent with the
structured path form when a redirect or application link retains context in a
query:

```elixir
# PhoenixTest: the current URL may be /chambers/secrets?clue=diary
assert_path(session, "/chambers/secrets")

# Fluffy: keep the path-only assertion
expect(session, Page.to_have_url(path: "/chambers/secrets"))
```

Use an exact string when the absence of a query or its serialized order is part
of the assertion. When the original specifies `query_params:`, use exact query
mode (the default) to preserve PhoenixTest's complete decoded-map comparison:

```elixir
expect(
  session,
  Page.to_have_url(
    path: "/chambers/secrets",
    query: %{"state" => "open", "clues[]" => ["diary", "basilisk"]}
  )
)
```

Use `query_mode: :subset` only when unrelated names are intentionally allowed.
Both modes ignore order between distinct names and preserve the order and
duplicates of repeated values for each name. Query names and values are
strings; bracketed names such as `clues[]` remain literal URLSearchParams names
rather than being converted into nested Plug data. Bare parameters and empty
values both decode to `""`; `+` and `%20` both decode to a space.

Static and LiveView drivers reproduce declarative server/HTML behavior. They also
model the pinned, stock Phoenix.HTML `data-method`/`data-to` hidden-form
action for plain elements, including links and buttons. A form-owned button
whose `phx-click` consists solely of `JS.dispatch("change")` is also supported:
Fluffy sends the current form fields and the clicked button's `name=value`
through the owning `phx-change`.
This is a narrow declarative convention, not a general JavaScript evaluator.

Static and LiveView do not execute arbitrary DOM handlers, custom
`phoenix.link.click` listeners, general `JS` command side effects, or browser
request streams. They ignore `data-confirm` before continuing with the
structural action; use Playwright when the prompt or cancellation outcome
itself matters. A `phx-update="ignore"` widget populated by application
JavaScript may require a narrow LiveView `unwrap/2` event or a Playwright-native
interaction, depending on whether the original test ran in-process or in a
browser.

## Advanced migration cases

Most migrations stay on Fluffy's shared API. The cases below deliberately
cross into driver-native behavior or application-specific test setup.

### Native `unwrap/2` differences

Fluffy keeps PhoenixTest's top-level `unwrap/2` name but deliberately changes
LiveView result handling:

- Static callbacks receive and must return the updated `Plug.Conn`.
- LiveView callbacks receive the current `Phoenix.LiveViewTest.View`, but Fluffy
  ignores the successful return value and reconciles the retained View.
- Playwright callbacks receive a typed `Fluffy.Playwright.Handle`, not a
  mutable session map; their successful return value is also ignored.

Remove PhoenixTest continuation tuples such as `{:ok, view, metadata}`. Write
the native action naturally and continue the pipeline:

```elixir
session
|> unwrap(fn view ->
  Phoenix.LiveViewTest.render_change(view, "validate", %{"name" => "Basilisk"})
end)
|> expect(visible(by_text("Basilisk")))
```

Do not call `assert_patch` or `assert_redirect` inside the callback: Fluffy
consumes those pending notifications to update session URL/history and perform
driver reclassification. Assert the resulting URL or page through Fluffy
after `unwrap/2`. Native exceptions, throws, and exits are not translated, so
an existing `catch_exit/1` around an expected LiveView failure can remain.

Raw Playwright page/context lifecycle mutations should move to
`wait_for(Event.popup(...))`, `switch_page`, `close_page`, and the other typed
event APIs. Use `Fluffy.Playwright.evaluate/2` for active-page JavaScript
value queries. Keep `unwrap/2` for uncommon page-local operations such as
selection, clock control, or emulation, and match native error tuples in the
callback.

Use this order when deciding whether native access is still necessary:

1. Prefer a shared Fluffy action, locator, expectation, or page operation.
2. Use `wait_for(Event.*(...))` when the operation causes a download, popup,
   navigation, dialog, request, or response.
3. Use `Fluffy.Playwright.evaluate/2,3` when a browser-only test needs a
   serializable value from the active page.
4. Use `unwrap/2` for an uncommon native operation such as browser clock
   control, viewport protocol assertions, or an application-specific API.

`evaluate/2,3` returns a value rather than a session. Keep a surrounding
pipeline with `then/2`:

```elixir
session
|> then(fn session ->
  assert Fluffy.Playwright.evaluate(session, "document.readyState") == "complete"
  session
end)
|> click(by_role(:button, name: "Open chamber"))
```

For application-specific JavaScript controls, preserve the original backend
and narrow the escape hatch to the missing interaction. Keep surrounding
navigation and assertions on the public Fluffy API. A server-side
`render_change/2` workaround does not, by itself, turn a Phoenix test into a
browser test.

### LiveView document boundary

The LiveView driver's locator and action DOM is the tree owned by the current
`Phoenix.LiveViewTest.View`. It deliberately does not merge the initial HTTP
document's dead layout around `[data-phx-main]` into that tree. This keeps
locator resolution, event dispatch, and LiveViewTest ownership aligned: an
element cannot appear actionable through Fluffy when LiveViewTest has no View
capable of receiving its event.

PhoenixTest follows the same ordinary LiveView boundary. Its LiveView assertions
and actions use `Phoenix.LiveViewTest.render(view)`, although its session struct
also retains the original `conn.resp_body` as a raw, initial-document escape
hatch. That body is not reconciled after LiveView events. Do not treat a stale
response as evidence that a later interaction succeeded.

Classify dead-layout coverage by its actual intent:

- If the test only checks links or content in the initial server response,
  retain it as a direct `Phoenix.ConnTest` response assertion. It is a
  response-rendering contract, not a LiveView interaction.
- If the test interacts with or observes the dead layout as part of the browser
  document, migrate it to Fluffy Playwright. The browser owns the full DOM.
- `unwrap/2` is not a dead-layout escape hatch for a LiveView page. Its callback
  receives only the current `Phoenix.LiveViewTest.View`.

### Prepared test connections

A controller test can inject a `Plug.Conn` whose assigns already carry
application-specific computed state. A Fluffy Phoenix session follows normal
request and session processing: it preserves the first-request connection,
but cannot promise that application plugs will retain test-only decorated
assigns. Keep a legacy direct-connection test when the route only passes with
that injected state; fix the application contract before converting it to a
browser-shaped test.

Fluffy does not provide a Playwright connect-param override. Browser tests
exercise the params supplied by the application's real `LiveSocket`.

For one initial Phoenix mount, prepare the session's one-shot connection:

```elixir
conn =
  Phoenix.ConnTest.build_conn()
  |> Phoenix.LiveViewTest.put_connect_params(%{"timezone" => "Europe/Berlin"})

start_session(:phoenix, conn: conn)
|> visit("/chambers/secrets")
```

`unwrap/2` is not a substitute: a LiveView callback receives the View only after
its mount has consumed the connect params. A test whose subject is injected
connect params surviving later navigation should stay in direct LiveViewTest;
Fluffy intentionally does not carry test-only params across fresh requests.

### Migration automation limits

A future Igniter migration can safely assist only with syntax whose semantics
are known: imports, renamed constructors, and guarded `at:` to `nth/2`
translations. It must report—not rewrite—ambiguous active-form submission,
ARIA-role, JavaScript, and visibility cases.

## Final cleanup

After every source test has been classified and migrated:

1. Search for both PhoenixTest case modules and direct `import PhoenixTest`
   statements. Do not remove the dependency while either remains.
2. Remove PhoenixTest/PhoenixTestPlaywright case templates, runtime children,
   configuration, dependencies, and lock entries that no longer have callers.
3. Retain direct `Phoenix.ConnTest` and `Phoenix.LiveViewTest` protocol tests;
   they were never migration targets.
4. Compile with warnings as errors, inspect the resolved dependency tree, and
   run the migrated focused modules on their preserved backends.
5. Run the broader suite only after the incremental migration is internally
   consistent; broad runs are a final integration check, not the feedback loop
   for each rewrite.

The [capability matrix](capabilities.md) defines the release boundary.
