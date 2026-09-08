# Migrating from PhoenixTest

Fluffy replaces PhoenixTest helpers with composable locators, explicit form
submission, and a shared Phoenix/Playwright API. This guide covers the setup
and behavior differences that matter when converting tests.

## Test-module setup

Replace PhoenixTest-specific setup with the shared
[`FluffyCase` recipe](usage.md#shared-test-case). It imports the API, creates a
session, and lets module, describe, or test tags choose the backend. Keep your
ordinary `ConnCase` for fixtures, routes, and sandbox setup.

See [Installation and runtime](installation.md) for endpoint, Playwright, and
Ecto sandbox configuration.

## Common rewrites

Start with these common translations; matching and form differences are
explained below:

| PhoenixTest | Fluffy |
| --- | --- |
| `visit("/potions")` | `visit("/potions")` after `start_session/2` |
| `fill_in("Potion name", with: name)` | `fill(by_label("Potion name", exact: true), name)` |
| `select("Boomslang skin", from: "Ingredient")` | `select_option(by_label("Ingredient", exact: true), %{label: "Boomslang skin"})` |
| `check("Ready to brew")` | `check(by_label("Ready to brew", exact: true))` |
| `uncheck("Ready to brew")` | `uncheck(by_label("Ready to brew", exact: true))` |
| `click_button("Brew potion")` | `click(by_role(:button, name: "Brew potion"))` |
| `click_link("Potions")` | `click(by_role(:link, name: "Potions"))` |
| `assert_has("#notice")` | `expect(to_be_visible(by_css("#notice")))` |
| `assert_path("/potions")` | `expect(Page.to_have_url(path: "/potions"))` |
| `assert_path("/potions", query_params: params)` | `expect(Page.to_have_url(path: "/potions", query: params))` |
| `assert_has("title", text: "Potions", exact: true)` | `expect(Page.to_have_title("Potions"))` |
| `reload_page()` | `reload()` |
| `upload("Recipe", path)` | `set_input_files(by_label("Recipe", exact: true), path)` |
| `submit()` | `submit(by_css("#potion-form"))` |

Use `%{value: value}`, `%{label: label}`, or `%{index: zero_based_index}` when
the selection criterion must be explicit. One `select_option` call replaces
the selected set; pass a list for a multiple select.

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
expect(session, nth(by_css(".creature"), 0) |> to_be_visible())
```

Explicit ARIA roles override the element's default role:
`<a role="menuitem">Edit</a>` is located as a `:menuitem`. In a browser test,
first perform the interaction that makes a JavaScript-owned menu
visible. In a Phoenix test, a structurally actionable `href`, `phx-click`, or
submit control can be targeted directly when opening the menu is purely
client-side presentation.

### Exact matching

PhoenixTest's `exact:` default depends on the helper; Fluffy follows
Playwright locator defaults:

| Source operation | PhoenixTest default | Fluffy translation |
| --- | --- | --- |
| `fill_in`, `select`, `check`, `uncheck`, `choose`, and `upload` label lookup | exact | put `exact: true` on `by_label` |
| `select` option text (`exact_option`) | exact | `%{label: text}` already selects an exact option label |
| `assert_has` and `refute_has` text | substring | omit `exact:` or use `exact: false` on the semantic locator |
| `click_button` and `click_link` text | substring | omit `exact:` or use `exact: false` on `by_role` |

For assertions, put exactness on the locator rather than the expectation:

```elixir
# assert_has("p", text: "Potion brewed", exact: true)
expect(by_text(by_css("p"), "Potion brewed", exact: true) |> to_be_visible())

# assert_has("p", text: "Potion brewed")
expect(by_text(by_css("p"), "Potion brewed", []) |> to_be_visible())
```

Prefer labels and roles over generated IDs or CSS tied to implementation
details. Compose locators to identify the intended row, section, or control;
keep CSS when the test specifically checks structure or no suitable semantic
locator exists.

Prefer direct state assertions too: `to_be_enabled(by_label("Potion name"))`
requires the field to exist and be enabled, whereas checking that no disabled
input matches can pass when the field is missing. Use `to_have_value` for
field values and `to_be_checked` for checkbox state.

PhoenixTest's `exact:` on a `value:` or `selected:` assertion applies to its
optional field label, not to the value or selected option itself. Preserve
that distinction by applying `exact:` only to the locator used to find the
field.

## Assertion intent

Choose whether the old assertion meant DOM absence or user-visible state:

```elixir
# The node must not exist.
session |> expect(by_css("#flash") |> to_have_count(0))

# The node may exist but must not be visible.
session |> expect(not_(by_css("#flash") |> to_be_visible()))
```

`not_(to_be_visible(...))` checks visibility; `to_have_count(..., 0)` checks
absence.

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

Form behavior to account for:

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
- Static and LiveView bypass native constraint validation. Use Playwright for
  validation events, browser-specific serialization, and JavaScript-mutated
  `FormData`; see [Forms and files](capabilities.md#forms-and-files).

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

`press(locator, "Enter")` follows implicit submission rules: it may select a
default submitter or decline to submit. Use it when the key interaction itself
is under test.

### Files and uploads

The same public action covers ordinary multipart forms and managed LiveView
uploads:

```elixir
session
|> set_input_files(by_label("Evidence"), ["diary-front.pdf", "diary-back.pdf"])
|> click(by_role(:button, name: "Upload"))
```

The path list preserves selection order. Pass `[]` to clear the input.
For generated bytes, use `%Fluffy.FilePayload{}`. For a JavaScript-opened file
chooser, use Playwright's `Event.file_chooser`. See
[Files and uploads](usage.md#files-and-uploads) and
[File choosers](advanced-events.md#file-choosers) for examples.

## Navigation, retries, and JavaScript

`expect(Page.to_have_url(...))` compares an exact canonical absolute URL, a
regular expression over that complete URL, or selected structured components.
Root-relative exact strings are resolved against `base_url`. LiveView expectations
retry fresh renders under one deadline and wake on redirects/process exits.
LiveView actions also resolve afresh while a target is
absent, disabled, structurally hidden for a click, readonly for a fill, or
missing the requested select option. Multiple matches and semantically wrong
control types still fail immediately, and Static actions remain immediate.

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

Phoenix supports declarative server/HTML actions, including stock
Phoenix.HTML `data-method`/`data-to` behavior and a form button's
`JS.dispatch("change")`. It does not execute arbitrary JavaScript.
`data-confirm` is ignored; use Playwright to test the prompt or cancellation.
JavaScript-populated `phx-update="ignore"` controls may need a native LiveView
event or a browser interaction. See [Capability matrix](capabilities.md) for
the supported boundaries.

## Playwright events, pages, and independent users

Replace raw event recorders with Fluffy's listener-before-action API. The
listener is installed before the callback runs, and the captured result stays
in the pipe:

```elixir
alias Fluffy.Download

session
|> wait_for(Event.download(:report), fn session ->
  click(session, by_role(:button, name: "Download potion ledger"))
end)
|> expect(Download.to_have_suggested_filename(:report, "potions.csv"))
```

For popups, use `Event.popup` with `switch_page` and `close_page` instead of
changing native page IDs. Start a second session for an independent user;
pages within one session share cookies and storage. See
[Advanced events and pages](advanced-events.md) for popup, dialog, navigation,
and network examples.

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
|> expect(by_text("Basilisk") |> to_be_visible())
```

Do not call `assert_patch` or `assert_redirect` inside the callback: Fluffy
consumes those pending notifications to update session URL/history and perform
driver reclassification. Assert the resulting URL or page through Fluffy
after `unwrap/2`. Native exceptions, throws, and exits are not translated, so
an existing `catch_exit/1` around an expected LiveView failure can remain.

Use the event and page APIs for browser lifecycle operations, and
`Fluffy.Playwright.evaluate/2` for JavaScript values. Reserve `unwrap/2` for
native operations without a shared API. See
[Native escape hatch](usage.md#native-escape-hatch) and
[Browser-only evaluation](usage.md#browser-only-evaluation).

### LiveView document boundary

Like PhoenixTest, Fluffy's LiveView driver sees the current View's DOM, not
the surrounding dead layout. Use `Phoenix.ConnTest` for initial outer-layout
HTML assertions or Playwright for interactions with the full document.
LiveView `unwrap/2` receives only the View; it cannot access the outer layout.

### Prepared test connections

Pass `conn:` when the first Phoenix request needs a prepared connection.
Application plugs may replace test-only assigns during normal request
processing.

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

The prepared connection applies only to the first request; connect params do
not carry across later navigation. `unwrap/2` runs after mounting, so it is too
late to supply initial connect params.
