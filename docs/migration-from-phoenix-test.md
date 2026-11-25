# Coming from PhoenixTest

Rewrite your tests on Fluffy's native API. This is the recommended path for
PhoenixTest.Playwright suites: the helpers PhoenixTest.Playwright adds, such as `evaluate`,
keyboard input, cookies and direct Playwright calls, are native Fluffy calls, so the
whole suite reads in one style. [Rewrite on the native API](#rewrite-on-the-native-api)
maps PhoenixTest's common helpers to native steps.

The `Fluffy.PhoenixTest` facade keeps PhoenixTest's `visit`, `fill_in`, `click_button`,
`assert_has`, `assert_path`, `within` and `submit`, so tests change little. It fits plain
PhoenixTest suites that use none of PhoenixTest.Playwright's extras, and works as a
temporary step for a large suite. Anything beyond PhoenixTest's API goes through `unwrap`
or `facade.session`; once a suite needs them for more than a few calls, rewrite it on the
native API rather than mix the two styles. [Use the facade](#use-the-facade) covers its
setup and differences.

For what you gain, see [Why Fluffy](why-fluffy.md).

## Drop waits Fluffy does for you

LiveView assertions retry and supported actions wait for their target by default, for up to
`phoenix_backend_timeout` (1 s, set under `config :fluffy`). A `timeout:` added only to wait can go
if that's long enough; keep a longer one where the page takes longer. In the browser, a visit waits for the LiveView to connect,
so drop `assert_has("body .phx-connected")` after each visit; keep assertions for your
application's own loading. See [Actionability checks and waiting](actions.md#actionability-checks-and-waiting).

## Check assertions on layout content

LiveView tests see the root layout, `live_title` and portal content, as the browser does. A
`refute_has` or `count:` that relied on layout content being absent can now fail, and title
assertions include `live_title`'s prefix and suffix.
See [LiveView document and patch boundaries](capabilities.md#liveview-document-and-patch-boundaries).

## Rewrite on the native API

Replace `import PhoenixTest` with `import Fluffy`, `import Fluffy.Locator`, and
`use Fluffy.Assert`, after your `ConnCase` and `use Playwright.Test`, and start the
session in a setup; see [Your first test](usage.md#your-first-test) and
[Shared test case](usage.md#shared-test-case) for complete setup, and
[Logging in](usage.md#logging-in) for a prepared connection. The `ConnCase` keeps owning
the sandbox ([Ecto sandbox](installation.md#ecto-sandbox)).

Each PhoenixTest helper, as the facade keeps it, becomes a pipeline step (`button` and `link`
need `import Fluffy.Locator.Roles`):

| PhoenixTest | Native locator API |
| --- | --- |
| `fill_in("Name", with: name)` | `fill(by_label("Name", exact: true), name)` |
| `select("Boomslang skin", from: "Ingredient")` | `select_option(by_label("Ingredient", exact: true), %{label: "Boomslang skin"})` |
| `check("Ready")` | `check(by_label("Ready", exact: true))` |
| `uncheck("Ready")` | `uncheck(by_label("Ready", exact: true))` |
| `click_button("Brew")` | `click(button("Brew"))`, or `click(by_role(:button, name: "Brew"))` |
| `click_link("Potions")` | `click(link("Potions"))`, or `click(by_role(:link, name: "Potions"))` |
| `refute_has("#notice")` | `refute_has(by_css("#notice"))` |
| `assert_has("#notice", count: 0)` | `assert(count(by_css("#notice") \|> filter(visible: true), 0))` |
| `assert_path("/potions")` | `assert(page_url(&(&1.path == "/potions")))` |
| `assert_path("/potions", query_params: params)` | `assert(page_url("/potions?" <> URI.encode_query(params)))` when the query order is known, or a predicate |
| `assert_has("title", text: "Potions", exact: true)` | `assert(page_title("Potions"))` |
| `reload_page()` | `reload()` |
| `upload("Recipe", path)` | `set_input_files(by_label("Recipe", exact: true), path)` |
| `submit()` | `submit(by_css("#potion-form"))` |

When rewriting, preserve the original assertion's intent:

- Native `assert_has` and `refute_has` (like `visible`) use the same visibility rules but reject multiple matches.
  For DOM presence/absence, use counts as described in [Visibility and DOM presence](assertions.md#visibility-and-dom-presence).
- Native text, role-name, and label locators default to substring matching;
  use `exact: true` to retain exact field labels. Facade `text:` without `exact: true` ignores
  case, except on `"title"`; native `text` and `contain_text` don't, so pass `ignore_case: true`
  to keep that. Native `nth` is zero-based and counts
  hidden matches, whereas facade `at: n` is one-based among visible matches:
  `filter(visible: true) |> nth(n - 1)`. Use locator composition in place of facade
  `within`; see
  [Locators](locators.md#locators).
- Native `page_title("Potions")` is an exact normalized match. Use a regex
  for an intentional substring title assertion. Native URL strings match the
  complete URL; use a predicate such as `page_url(&(&1.path == "/x"))` to retain path-only intent. See
  [Page assertions](assertions.md#page-assertions).
- The native API does not track an active form. Select a form explicitly for
  `submit`, or click the intended submitter. The facade continues to support
  active-form tracking.

## Coming from PhoenixTest.Playwright

For what PhoenixTest.Playwright adds:

- **Setup:** drop `PhoenixTest.Playwright.Supervisor` from `test_helper.exs` and replace
  `config :phoenix_test` as [Installation and runtime](installation.md) shows: `timeout`
  becomes `action_timeout`, `navigation_timeout` and `expect: [timeout: ...]`, `trace: true`
  and `screenshot: true` become `:on`, and `browser_launch_timeout` moves into
  `launch_options`. Add `/test-results/` to `.gitignore`. Drop a `runtime: false` from the
  dependency: sessions need Fluffy's application started. PhoenixTest.Playwright's `js_logger` becomes a
  listener ([Console, page errors, and page lifecycle](advanced-events.md#console-page-errors-and-page-lifecycle)).
- **`use PhoenixTest.Playwright.Case`:** `use Playwright.Test`, and start the sandbox owner and
  session in your own setup ([Ecto sandbox](installation.md#ecto-sandbox),
  [Shared test case](usage.md#shared-test-case)). A context option
  tag such as `browser_context_opts` becomes `@tag Playwright.Test.use(...)`.
- **Extra helpers** are native calls; on the facade, they take `facade.session`
  ([Using native Fluffy APIs](#using-native-fluffy-apis)).
  They take a locator where PhoenixTest.Playwright took a selector: a CSS selector goes in
  `Fluffy.Locator.by_css/1`, and `Selector.role/3` or `Selector.text/2` become `by_role/2` or
  `by_text/2`. They don't see the facade's `within` scope, so scope the locator yourself.
  - `evaluate`: `Fluffy.Playwright.evaluate/3`, with `arg:` positional and no `is_function:`;
    it returns the value instead of passing it to a callback. JavaScript run for its effect
    in a pipeline becomes `unwrap(&Playwright.Page.evaluate!(&1, js, arg))` (`Fluffy.unwrap/2`,
    or on the facade `Fluffy.PhoenixTest.unwrap/2`, which keeps the facade session);
  - `click(selector)` and `press`: `Fluffy.click/3` and `Fluffy.press/4`; `click`'s text
    argument becomes `filter(has: by_text(text))`, or `by_text(text)` chained under the
    selector before PhoenixTest.Playwright 0.16, which clicked the text itself;
  - `type`: `Fluffy.Playwright.press_sequentially/4`;
  - `drag`: `Fluffy.Playwright.drag_to/4`;
  - `add_cookies` and `clear_cookies`: `Fluffy.add_cookies/2` and `Fluffy.clear_cookies/2`;
    cookies are maps that need a `url:` (such as `Fluffy.base_url/1`), with `expires:`
    instead of `max_age:`;
  - `add_session_cookie`: same name, other arguments. `add_session_cookie(conn, [value: values], options)`
    becomes `Fluffy.add_session_cookie(session, values)`, with the options from the endpoint's
    `session_options/0` ([Logging in](usage.md#logging-in)). On the facade, call it before the
    session enters it, as `Fluffy.start_session(:playwright) |> Fluffy.add_session_cookie(values) |> visit("/")`;
  - `screenshot` and `assert_screenshot`: `Fluffy.Playwright.screenshot/2` (with `path:`,
    and `full_page: true` for the old default; it returns the PNG, not the session) and
    `Fluffy.Assert.page_match_screenshot/1` or `Fluffy.Expect.page_to_have_screenshot/1` (with `name:`);
  - `with_dialog`: see [Listeners and dialogs](advanced-events.md#listeners-and-dialogs);
  - `assert_download`: wait for `Fluffy.Event.download/1`, then `Fluffy.Download.read/2` or
    `Fluffy.Download.save_as/2` ([Downloads](advanced-events.md#downloads)). The event comes
    when downloading starts; reading or saving waits for completion and raises on failure,
    which PhoenixTest.Playwright's read of the file checked.
- **`assert_has` and `refute_has` with `text:`:** PhoenixTest.Playwright checked the element
  holding the text inside the selector; the facade checks the selector's element, as
  PhoenixTest does. When that element is never visible, such as a modal's zero-size
  wrapper, `assert_has` fails and `refute_has` passes even while the text shows, so select
  the visible element, such as the modal's `[role='dialog']`.
- **`check` and `uncheck`:** PhoenixTest.Playwright ignored Playwright's "Clicking the
  checkbox did not change its state"; Fluffy raises it, as Playwright does, on both backends.
  It means the app set the box back after the click, such as a hook mirroring server state:
  click it and assert `checked` instead. A click toggles, so do this only where the test knows
  the box's state before.
- **Direct `PlaywrightEx` calls:** use playwright_ex 1.65's `Playwright` API through `unwrap`,
  whose callback gets the `Playwright.Page` instead of a map. It returns JS `null` as `:null`.

## Use the facade

Replace `import PhoenixTest` with `import Fluffy.PhoenixTest`, including imports
in your shared case module. Import the facade on its own; mixing it with
`import Fluffy` introduces overlapping function names.

After completing [Installation and runtime](installation.md), keep your application's
`ConnCase`, and add `use Playwright.Test` after it. A prepared connection can still be piped
directly into `Fluffy.PhoenixTest.visit/2`:

```elixir
defmodule MyAppWeb.PotionTest do
  use MyAppWeb.ConnCase, async: true
  use Playwright.Test
  import Fluffy.PhoenixTest

  test "saves a potion", %{conn: conn} do
    conn
    |> visit("/potions/new")
    |> within("#potion-form", fn session ->
      session
      |> fill_in("Name", with: "Polyjuice")
      |> click_button("Save")
    end)
    |> assert_path("/potions")
    |> assert_has("#notice", text: "Saved")
  end
end
```

Keep existing fixture and authentication setup. The `ConnCase` keeps owning the
sandbox (`start_owner!`); the required endpoint and sandbox configuration lives in
[Installation and runtime](installation.md#ecto-sandbox).

## Using native assertions alongside the facade

The facade's `assert_has` and `refute_has` accept selectors or a `%Fluffy.Locator{}`
and options such as `text:` and `count:`. The similarly named `Fluffy.Assert`
helpers take native locators and are visibility shortcuts; native count assertions
remain explicit with `assert(session, count(locator, n))`.

If using `Fluffy.Assert` alongside the facade, exclude its overlapping names:

```elixir
use Fluffy.Assert
import Fluffy.Assert, except: [assert_has: 2, assert_has: 3, refute_has: 2, refute_has: 3]
import Fluffy.PhoenixTest
```

Native assertions take the contained native session (`session.session`), while
facade assertions take the facade session.

## Phoenix and browser tests in the same module

Piping a connection into `Fluffy.PhoenixTest.visit/2` always starts a Phoenix session.
To choose a backend, start a session explicitly. The same facade calls work with both:

```elixir
defmodule MyAppWeb.PotionTest do
  use MyAppWeb.ConnCase, async: true
  use Playwright.Test
  import Fluffy.PhoenixTest

  setup context do
    %{session: start_session(context[:backend] || :phoenix)}
  end

  test "lists the available potions", %{session: session} do
    session
    |> visit("/potions")
    |> assert_has("h2", text: "Polyjuice Potion")
  end

  @tag backend: :playwright
  test "brews a potion through a JavaScript hook", %{session: session} do
    session
    |> visit("/potions")
    |> click_button("Brew potion")
    |> assert_has("#notice", text: "Potion brewed")
  end
end
```

The setup above interprets the tag; Fluffy does not select a backend from tags
by itself. To share it across tests, move `use Playwright.Test`, the facade import and this
setup into your case template's `using` (see [Shared test case](usage.md#shared-test-case)).
Module and describe tags work with the same setup. See [Choosing a backend](usage.md#choosing-a-backend) for guidance
and [Playwright setup](installation.md#playwright-setup) for browser installation.

## What stays familiar, and what to check

The facade preserves PhoenixTest vocabulary and conveniences:

- Field actions use exact labels by default. `within` scopes a callback, and
  field actions remember their owning form for `submit()`.
- Without a field predicate, `assert_has` and `refute_has` check visibility; hidden
  or absent elements satisfy `refute_has`. Static and LiveView check structural
  visibility, while Playwright checks rendered visibility. `count:` and one-based
  `at:` count visible matches only; field predicates without `at:` add no visibility
  requirement. They retain familiar text and field predicates.
- `assert_path` remains a path assertion; use `query_params:` when the query
  is part of the assertion.

The facade uses Fluffy's execution engine, so it is not an exact compatibility
implementation. Check these differences when migrating:

- **Strict matching:** actions reject ambiguous matches; see [Locators](locators.md#locators).
- **Exact text:** `exact: true` normalizes whitespace but does not ignore soft hyphens or
  zero-width spaces in the page text.
- **CSS links:** text matches take precedence over labels. Label matching is a
  fallback only when no text match exists when the action starts.
- **Form behavior:** submissions use current DOM ownership and control state.
  See [Form submission and keyboard actions](actions.md#form-submission-and-keyboard-actions)
  and [Forms and files](capabilities.md#forms-and-files) for supported behavior.
- **JavaScript and timing:** choose Playwright for browser-owned behavior. The
  [capability matrix](capabilities.md) is the reference for driver boundaries,
  including LiveView debounce/throttle timing and the document boundary.
- **Native callbacks:** remove PhoenixTest continuation tuples such as
  `{:ok, view, metadata}` from `unwrap` callbacks. Follow the return-value rules
  in [Native escape hatch](debugging.md#native-escape-hatch), then assert the outcome
  with `assert_has` or `assert_path` in the facade pipeline.
- **Downloads:** there is no facade `assert_download/2`. Use the native
  [event API](advanced-events.md#downloads) when testing downloads.

The `Fluffy.PhoenixTest` API reference is authoritative for supported overloads,
matching defaults, options, and rejected combinations. Unsupported options raise
`ArgumentError`.

### Prepared connections

`put_endpoint(conn, endpoint)` overrides Fluffy's configured endpoint for that
connection. For initial LiveView connect params, prepare the connection before
visiting:

```elixir
conn
|> Phoenix.LiveViewTest.put_connect_params(%{"timezone" => "Europe/Berlin"})
|> visit("/chambers/secrets")
```

The prepared connection applies to the first request only, except that its `accept`,
`accept-language` and `authorization` headers go with every request, as
`Phoenix.ConnTest.recycle/2` keeps them, and so does its `user-agent`, as a browser's would. Connect params do not carry across later navigation, and `Fluffy.PhoenixTest.unwrap/2` runs too late to supply
initial mount params. Browser tests use the application's real LiveSocket parameters.

### Using native Fluffy APIs

Facade operations return a `Fluffy.PhoenixTest.Session` wrapper. Native Fluffy
operations accept its contained `session` field:

```elixir
facade = start_session(:playwright) |> visit("/potions")
title = Fluffy.Playwright.evaluate(facade.session, "document.title")
assert title == "Potions"
```

This suits a few calls. When tests need them throughout, for browser scripting, pages
or events, [rewrite on the native API](#rewrite-on-the-native-api) rather than mix the two
styles. See [Advanced events and pages](advanced-events.md) for those workflows.
