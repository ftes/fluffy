# Coming from PhoenixTest

Start with `import Fluffy.PhoenixTest`. This facade makes Fluffy mostly a
drop-in replacement for supported PhoenixTest helpers: keep `visit`, `fill_in`,
`click_button`, `assert_has`, `assert_path`, `within`, and `submit` in your tests.
You do not need to rewrite them into locators to adopt Fluffy or use Playwright.

## Replace the import and add lifecycle setup

Replace `import PhoenixTest` with `import Fluffy.PhoenixTest`, including imports
in your shared case module. Import the facade on its own; mixing it with
`import Fluffy` introduces overlapping function names.

After completing [Installation and runtime](installation.md), keep your
application's `ConnCase` and add `Fluffy.Test.setup/1` after its setup. A prepared
connection can still be piped directly into `visit/2`:

```elixir
defmodule MyAppWeb.PotionTest do
  use MyAppWeb.ConnCase, async: true
  import Fluffy.PhoenixTest

  setup context do
    Fluffy.Test.setup(context)
  end

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

Keep existing fixture and authentication setup. Fluffy adopts an existing
sandbox checkout; the required endpoint and sandbox configuration lives in
[Installation and runtime](installation.md#ecto-sandbox). If your shared case
already calls `Fluffy.Test.setup/1`, do not call it again in individual modules.

## Phoenix and browser tests in the same module

Piping a connection into `visit/2` always starts a Phoenix session. To choose
a backend, start a session explicitly. The same facade calls work with both:

```elixir
defmodule MyAppWeb.PotionTest do
  use ExUnit.Case, async: true
  import Fluffy.PhoenixTest

  setup context do
    :ok = Fluffy.Test.setup(context)
    %{session: start_session(Map.get(context, :backend, :phoenix))}
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
by itself. Move this setup and the facade import into your application's case
module when sharing it across tests. Module and describe tags work with the
same setup. See [Choosing a backend](usage.md#choosing-a-backend) for guidance
and [Playwright setup](installation.md#playwright-setup) for browser installation.

## What stays familiar, and what to check

The facade preserves PhoenixTest vocabulary and conveniences:

- Field actions use exact labels by default. `within` scopes a callback, and
  field actions remember their owning form for `submit()`.
- `assert_has` and `refute_has` check DOM presence, including hidden elements.
  They retain one-based `at:` positions and familiar text and field predicates.
- `assert_path` remains a path assertion; use `query_params:` when the query
  is part of the assertion.

The facade uses Fluffy's execution engine, so it is not an exact compatibility
implementation. Check these differences when migrating:

- **Strictness and waiting:** single-target actions reject ambiguous matches.
  Static checks immediately; LiveView retries supported transient states.
  See [Actionability checks and waiting](usage.md#actionability-checks-and-waiting).
- **Form behavior:** submissions use current DOM ownership and control state.
  See [Form submission and keyboard actions](usage.md#form-submission-and-keyboard-actions)
  and [Forms and files](capabilities.md#forms-and-files) for supported behavior.
- **JavaScript and timing:** choose Playwright for browser-owned behavior. The
  [capability matrix](capabilities.md) is the reference for driver boundaries,
  including LiveView debounce/throttle timing and the document boundary.
- **Native callbacks:** remove PhoenixTest continuation tuples such as
  `{:ok, view, metadata}` from `unwrap` callbacks. Follow the return-value rules
  in [Native escape hatch](usage.md#native-escape-hatch), then assert the outcome
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

The prepared connection applies to the first request only. Connect params do
not carry across later navigation, and `unwrap/2` runs too late to supply initial
mount params. Browser tests use the application's real LiveSocket parameters.

### Using native Fluffy APIs

Facade operations return a `Fluffy.PhoenixTest.Session` wrapper. Native Fluffy
operations accept its contained `session` field:

```elixir
facade = start_session(:playwright) |> visit("/potions")
title = Fluffy.Playwright.evaluate(facade.session, "document.title")
assert title == "Potions"
```

Prefer the native API throughout tests centered on browser scripting, pages,
or events. See [Events and pages](advanced-events.md) for those workflows.

## Optional: adopt the locator API

Use the native API when composable locators make a test clearer. Replace the
facade import with `import Fluffy`, `import Fluffy.Locator`, and
`use Fluffy.Assert`; see [Your first test](usage.md#your-first-test) for complete
setup. This is an optional rewrite, separate from switching to Fluffy.

Each call below is a pipeline step:

| Facade | Native locator API |
| --- | --- |
| `fill_in("Name", with: name)` | `fill(by_label("Name", exact: true), name)` |
| `select("Boomslang skin", from: "Ingredient")` | `select_option(by_label("Ingredient", exact: true), %{label: "Boomslang skin"})` |
| `check("Ready")` | `check(by_label("Ready", exact: true))` |
| `uncheck("Ready")` | `uncheck(by_label("Ready", exact: true))` |
| `click_button("Brew")` | `click(by_role(:button, name: "Brew"))` |
| `click_link("Potions")` | `click(by_role(:link, name: "Potions"))` |
| `refute_has("#notice")` | `assert(count(by_css("#notice"), 0))` |
| `assert_path("/potions")` | `assert(page_url(path: "/potions"))` |
| `assert_path("/potions", query_params: params)` | `assert(page_url(path: "/potions", query: params))` with string keys and values |
| `assert_has("title", text: "Potions", exact: true)` | `assert(page_title("Potions"))` |
| `reload_page()` | `reload()` |
| `upload("Recipe", path)` | `set_input_files(by_label("Recipe", exact: true), path)` |
| `submit()` | `submit(by_css("#potion-form"))` |

When rewriting, preserve the original assertion's intent:

- Native `visible` adds a visibility requirement. For DOM presence/absence,
  use counts as described in [Visibility and DOM presence](usage.md#visibility-and-dom-presence).
- Native text, role-name, and label locators default to substring matching;
  use `exact: true` to retain exact field labels. Native `nth` is zero-based, whereas facade `at:` is
  one-based. Use locator composition in place of facade `within`; see
  [Locators](usage.md#locators).
- Native `page_title("Potions")` is an exact normalized match. Use a regex
  for an intentional substring title assertion. Native URL strings match the
  complete URL; use `page_url(path: ...)` to retain path-only intent. See
  [Page assertions](usage.md#page-assertions).
- The native API does not track an active form. Select a form explicitly for
  `submit`, or click the intended submitter. The facade continues to support
  active-form tracking.
