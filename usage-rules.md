# Fluffy usage rules

Fluffy runs Phoenix feature tests through one Playwright-shaped API, in-process or in a real browser. It is a test-only dependency.

## Setup

- `config :fluffy, endpoint: MyAppWeb.Endpoint` in `config/test.exs`. With Ecto, also `config :fluffy, ecto_repos: [MyApp.Repo]` and the sandbox plug and mount hook from `docs/installation.md`.
- Call `Fluffy.Test.setup(context)` exactly once per test, with or without Ecto, ideally in a shared case module.
- Browser tests need `server: true` on the endpoint, a `config :fluffy, playwright: [...]` block and `MIX_ENV=test mix playwright_ex.install -- chromium`. `MIX_ENV=test` is required because the driver arrives through a test-only dependency.

## Choosing an API and a backend

- Native API: `import Fluffy`, `import Fluffy.Locator`, and `use Fluffy.Assert` (or `import Fluffy.Expect`). PhoenixTest-style facade: `import Fluffy.PhoenixTest` on its own, never alongside `import Fluffy`, whose names overlap. Follow what the suite already uses.
- A suite coming from PhoenixTest can keep the facade. Native calls accept the facade's `facade.session`.
- `start_session(:phoenix)` is the default choice. Its first visit picks the Static or LiveView driver, and later navigations pick again. There is nothing to select between those two.
- `start_session(:playwright)` is for JavaScript, computed style and layout, native validation, dialogs, network events, tabs or focus.
- In the facade, `conn |> visit(path)` always starts a Phoenix session; use `start_session(:playwright) |> visit(path)` for a browser.
- Fluffy does not read test tags. To switch with `@tag backend: :playwright`, have the shared case call `start_session(Map.get(context, :backend, :phoenix))`.

```elixir
start_session(:phoenix)
|> visit("/creatures/new")
|> fill(by_label("Name"), "Basilisk")
|> click(by_role(:button, name: "Register"))
|> assert(visible(by_text("Creature registered")))
|> assert(page_url(path: "/creatures"))
```

## Locators

- Prefer, in order: `by_label` for form controls, `by_role(:button, name: ...)`, `by_text`, `by_test_id`, and `by_css` when nothing user-facing identifies the element.
- Text, role-name and label matching is substring by default; pass `exact: true` for a complete match.
- Locators are values. Scope with `by_role(parent, :row, name: "x")`, refine with `filter(has: ...)`, `first`, `last`, zero-based `nth`, `and_`, `or_`. Use `frame_locator` for iframes on Playwright.
- Single-target actions and native `visible` are strict and fail on several matches. Narrow the locator, or assert `count(locator, n)` when several are intended. Facade `assert_has` accepts any visible match.

## Assertions and waiting

- Do not assert readiness before acting. Playwright waits natively, LiveView retries actions and assertions until the timeout, and Static checks immediately. Pass `timeout:` to change a deadline.
- A Playwright `visit` already waits for LiveViews to connect, so do not assert `.phx-connected`.
- `use Fluffy.Assert` gives `assert(visible(l))` and `refute(visible(l))`, and ordinary ExUnit asserts still work. `import Fluffy.Expect` gives `expect(to_be_visible(l))` and `expect(not_(to_be_visible(l)))`. Both return the session.
- `refute(visible(l))` passes for an absent or invisible element. Use `assert(count(l, 0))` to require DOM absence.
- URL strings match the complete URL, including query and fragment. Use `page_url(path: "/x")` when only the path matters.
- There is no page status assertion. On Playwright, assert on `Event.response` instead.
- Phoenix drivers check structural visibility (`hidden`, `aria-hidden="true"`, `type="hidden"`) and do not compute CSS, so `display: none` alone counts as visible there. Use `:playwright` to test rendered visibility.

## Hidden inputs

- `visible` and a plain facade `assert_has` fail on hidden inputs, and role locators exclude them. Assert with CSS, without a visibility requirement:
  - Facade: `assert_has("#token", count: 1)`, `assert_has("#token", value: "x")`, `assert_has("#terms", checked: true)`.
  - Native: `assert(count(by_css("#token"), 1))`, `assert(value(by_css("#token"), "x"))`, `assert(checked(by_css("#terms")))`.
- A checkbox or radio hidden and styled through its label differs by backend. On Playwright, `check(by_label("Terms"))` resolves to the input and times out as it is not visible. Target the label: `set_checked(session, by_css("label[for=terms]"), true)`.
- On Static and LiveView a label target raises `Fluffy.OperationError` (not checkable). Target the input there with `by_label` or `by_css`, which works on hidden inputs. A test running on both backends needs a branch.

## Capabilities

- Check `docs/capabilities.md` before relying on a browser behaviour in a Phoenix test. Fluffy raises `Fluffy.CapabilityError` (fields `capability`, `driver`, `detail`) for what a driver cannot do, rather than ignoring it.
- Browser-only helpers live in `Fluffy.Playwright` (`hover`, `drag_to`, `press_sequentially`, `evaluate`, `new_page`, `switch_page`, ...), `Fluffy.Playwright.Keyboard`, `Mouse` and `Clock`.
- Playwright-only options, such as `by_role(:button, pressed: true)` or `click(l, force: true)`, raise `Fluffy.CapabilityError` on Phoenix.
- LiveView ignores `phx-debounce` and `phx-throttle`. Phoenix `click` ignores `data-confirm`. `press` raises on Static and only forwards the key to bound handlers on LiveView.

## Events, downloads and routes

- Register before the action. `pending = wait_for(session, Event.download())`, act, then `await(pending)`, once. In a pipeline, `assert_event(Event.download(), &click(&1, button), fn download -> ... end)`, or `expect_event` with `Fluffy.Expect`.
- Downloads work on every driver: `Download.read/2`, `Download.save_as/2`. Other events require Playwright.
- `Fluffy.Playwright.route/4` registers before the request and hands the handler a `Fluffy.Route`. Answer once with `Route.fulfill/2`, `continue/2`, `abort/2` or `fallback/2`; an unanswered request hangs until its action times out.
- `&` captures cannot nest, not even `&fun/1` inside another capture. `&on(&1, Event.dialog(), &Dialog.accept/1)` does not compile: bind `accept = &Dialog.accept/1` first.

## Dropping to PlaywrightEx

Prefer the shared API. For what it does not cover:

- `Fluffy.unwrap(session, fun)` passes a `%Plug.Conn{}` (Static, return the updated conn), `%Phoenix.LiveViewTest.View{}` (LiveView) or `%PlaywrightEx.Page{}` (Playwright), and returns the session. It raises on a Phoenix session before its first visit.
- `Fluffy.Playwright.unwrap(session, locator, fun)` passes the `%PlaywrightEx.Locator{}` for a Fluffy locator, resolved in the active page and through frame locators. A navigation it causes is adopted. It raises `Fluffy.CapabilityError` on Phoenix.
- `unwrap(response, &PlaywrightEx.Response.server_addr!/1)` reaches an event value's native counterpart and returns the callback's result.
- Use bang functions inside the callback so failures stop the test.
- Do not natively close the page or context, call `remove_all_listeners`, `set_default_timeout`, `set_default_navigation_timeout` or `set_content`, stop tracing, or pass `no_wait_after:` or `signal:`. Those break Fluffy's tracking.
- In a LiveView callback, do not consume `assert_patch` or `assert_redirect`; assert the resulting page after `unwrap`.

## Debugging

- Element actions fail with `Fluffy.OperationError`, whose `cause` holds the driver's error. Failed assertions are `ExUnit.AssertionError`.
- Set `artifact_dir` in the Playwright config to keep HTML and a screenshot of failures.
- `Fluffy.Playwright.trace(session, open: false)` records a trace, `step/3` names a group of steps in it, and `open_browser/1` opens the current page.
