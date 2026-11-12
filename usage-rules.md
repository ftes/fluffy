# Fluffy usage rules

Fluffy runs Phoenix feature tests through one Playwright-shaped API, in-process or in a real browser. It is a dev and test dependency (`only: [:dev, :test]`), never in production; a `lazy_html` the app lists `only: :test` must widen to match.

## Setup

- `config :fluffy, endpoint: MyAppWeb.Endpoint` in `config/test.exs`. With Ecto, also `config :fluffy, ecto_repos: [MyApp.Repo]` and the sandbox plug and mount hook from `docs/installation.md`, behind an `Application.compile_env` flag set in `config/test.exs` because Fluffy is not in production. The app's DataCase/ConnCase owns the sandbox (`Sandbox.start_owner!` and `stop_owner` in `on_exit`), used before `use PlaywrightEx.Test`; Fluffy only sends its metadata from browser sessions. A plain `Sandbox.checkout` does not work for browser tests.
- Add `use Fluffy.Case` after the app's `ConnCase` (never before it: the `test/3` imports clash), or `use PlaywrightEx.Test` after `use ExUnit.Case` in modules with browser tests (Phoenix-only modules need nothing). `Fluffy.Case` adds `use PlaywrightEx.Test`, `use Fluffy.Assert`, `import Fluffy`, `import Fluffy.Locator` and a `session` per test from the `backend` tag (`:phoenix` by default). A second `use PlaywrightEx.Test` in a module does nothing.
- Browser tests need `server: true` on the endpoint, `config :playwright_ex, :test` for the browser (`browser_name`, `launch_options`) and `mix playwright_ex.install -- chromium`. For a system browser, install with `--no-browsers` and set `launch_options: [executable_path: ...]`. Sessions use `PlaywrightEx.Test.BrowserPool.shared()`; on Firefox, use an exclusive browser (one browser per worker, like Playwright Test): `start_session(:playwright, browser: PlaywrightEx.Test.BrowserPool.exclusive())`. For more users, start more sessions, each in its own browser context.
- The browser opens the endpoint listener's address, such as `127.0.0.1`. Set `check_origin: false` on the endpoint only when its `url` host differs from that address, as a stock `localhost` does.

## Choosing an API and a backend

- Native API: `import Fluffy`, `import Fluffy.Locator`, and `use Fluffy.Assert` (or `import Fluffy.Expect`). PhoenixTest-style facade: `import Fluffy.PhoenixTest` on its own, never alongside `import Fluffy`, whose names overlap. Follow what the suite already uses; a new suite defaults to `use Fluffy.Assert` (`docs/assertions.md` compares the two).
- A suite coming from PhoenixTest can keep the facade. Native calls accept the facade's `facade.session`.
- `start_session(:phoenix)` is the default choice. Its first visit picks the Static or LiveView driver, and later navigations pick again. There is nothing to select between those two.
- `start_session(:playwright)` is for JavaScript, computed style and layout, native validation, dialogs, network events, tabs or focus.
- In the facade, `conn |> visit(path)` always starts a Phoenix session; use `start_session(:playwright) |> visit(path)` for a browser.
- Only `Fluffy.Case` reads a test tag: `@tag`, `@describetag` or `@moduletag backend: :playwright` picks the backend of its `session`.

```elixir
start_session(:phoenix)
|> visit("/creatures/new")
|> fill(by_label("Name"), "Basilisk")
|> click(by_role(:button, name: "Register"))
|> assert(visible(by_text("Creature registered")))
|> assert(page_url("/creatures"))
```

## Locators

- Prefer, in order: `by_label` for form controls, `by_role(:button, name: ...)`, `by_text`, `by_test_id`, and `by_css` when nothing user-facing identifies the element.
- Text, role-name and label matching is substring by default; pass `exact: true` for a complete match.
- Locators are values. Scope with `by_role(parent, :row, name: "x")`, refine with `filter(has: ...)`, `first`, `last`, zero-based `nth`, `and_`, `or_`. Use `frame_locator` for iframes on Playwright.
- Single-target actions and native `visible` are strict and fail on several matches. Narrow the locator, or assert `count(locator, n)` when several are intended. Facade `assert_has` accepts any visible match.

## Assertions and waiting

- Do not assert readiness before acting. Playwright waits natively, LiveView retries actions and assertions until the timeout, and Static checks immediately. Pass `timeout:` to change a deadline.
- `timeout: 0` checks once, unlike Playwright's no timeout; Playwright actions and waits reject it. For no timeout, pass `timeout: :infinity`, never Playwright's `0`.
- A Playwright `visit` already waits for LiveViews to connect, so do not assert `.phx-connected`.
- `use Fluffy.Assert` gives `assert(visible(l))` and `refute(visible(l))`, and ordinary ExUnit asserts still work. `import Fluffy.Expect` gives `expect(to_be_visible(l))` and `expect(not_(to_be_visible(l)))`. Both return the session.
- `refute(visible(l))` passes for an absent or invisible element. Use `assert(count(l, 0))` to require DOM absence.
- URL strings match the complete URL, including query and fragment. When only the path matters, use a regex or a predicate over the URL string: `page_url(&(URI.parse(&1).path == "/x"))`.
- There is no page status assertion. On Playwright, assert on `Event.response` instead.
- Static and LiveView check structural visibility (`hidden`, `type="hidden"`) and do not compute CSS, so `display: none` alone counts as visible there. `aria-hidden="true"` does not affect visibility; only `by_role` excludes it. Use `:playwright` to test rendered visibility.
- Text matching skips `<script>` and `<style>`, as in Playwright, so `assert_has("script", text: ...)` fails even with `count:`. Match attributes with `count:`, or read the text natively: `unwrap` on Static passes the conn (`conn.resp_body`), and on Playwright use `Fluffy.Playwright.evaluate(session, locator, "el => el.textContent")`.

## Hidden inputs

- `visible` and a plain facade `assert_has` fail on hidden inputs and inside `hidden` elements, even with an attribute selector such as `input[value='x']`, and role locators exclude them. Assert with CSS, without a visibility requirement:
  - Facade: `assert_has("#token", count: 1)`, `assert_has("#token", value: "x")`, `assert_has("#terms", checked: true)`.
  - Native: `assert(count(by_css("#token"), 1))`, `assert(value(by_css("#token"), "x"))`, `assert(checked(by_css("#terms")))`.
- A checkbox or radio hidden and styled through its label differs by backend. On Playwright, `check(by_label("Terms"))` resolves to the input and times out as it is not visible. Target the label: `set_checked(session, by_css("label[for=terms]"), true)`.
- On Static and LiveView a label target raises `Fluffy.OperationError` (not checkable). Target the input there with `by_label` or `by_css`, which works on hidden inputs. A test running on both backends needs a branch.

## Capabilities

- Check `docs/capabilities.md` before relying on a browser behavior in a Phoenix test. Fluffy raises `Fluffy.CapabilityError` (fields `capability`, `driver`, `detail`) for what a driver cannot do, rather than ignoring it.
- Browser-only helpers live in `Fluffy.Playwright` (`hover`, `drag_to`, `press_sequentially`, `evaluate`, `new_page`, `switch_page`, ...), `Fluffy.Playwright.Keyboard`, `Mouse` and `Clock`.
- Playwright-only options, such as `by_role(:button, pressed: true)` or `click(l, force: true)`, raise `Fluffy.CapabilityError` on Phoenix.
- LiveView ignores `phx-debounce` and `phx-throttle`. Phoenix `click` ignores `data-confirm`. `press` raises on Static and only forwards the key to bound handlers on LiveView.

## Events, downloads and routes

- Register before the action. `pending = wait_for(session, Event.download())`, act, then `await(pending)`, once. In a pipeline, `assert_event(Event.download(), &click(&1, button), fn download -> ... end)`, or `expect_event` with `Fluffy.Expect`.
- Downloads work on every driver: `Download.read/2`, `Download.save_as/2`. Other events require Playwright.
- `Fluffy.Playwright.route/4` registers before the request and hands the handler a `PlaywrightEx.Route`. Answer once with `PlaywrightEx.Route.fulfill!/2`, `continue!/2`, `abort!/2` or `fallback!/2`; an unanswered request hangs until its action times out. Don't block in a route handler (`receive`, `Process.sleep`, `GenServer` calls, database or Phoenix work); hand off to a `Task` and fulfil from it: `fn route -> Task.start(fn -> Route.fulfill!(route, json: Owlery.letters_for("Harry")) end) end`. The `Task` inherits `$callers`, so the Ecto sandbox works there.
- `&` captures cannot nest, not even `&fun/1` inside another capture. `&on(&1, Event.dialog(), &Dialog.accept!/1)` does not compile: bind `accept = &Dialog.accept!/1` first.

## Dropping to PlaywrightEx

Prefer the shared API. For what it does not cover:

- `Fluffy.unwrap(session, fun)` passes a `%Plug.Conn{}` (Static, return the updated conn), `%Phoenix.LiveViewTest.View{}` (LiveView) or `%PlaywrightEx.Page{}` (Playwright), and returns the session. It raises on a Phoenix session before its first visit.
- `Fluffy.Playwright.unwrap(session, locator, fun)` passes the `%PlaywrightEx.Locator{}` for a Fluffy locator, resolved in the active page and through frame locators. A navigation it causes is adopted. It raises `Fluffy.CapabilityError` on Phoenix.
- Events other than page events, downloads and file choosers deliver PlaywrightEx's values, as in Playwright: read a response with `PlaywrightEx.Response.status/1`, accept a dialog with `PlaywrightEx.Dialog.accept!/1`. `Fluffy.Playwright.page(session, native_page)` turns their page into a `Fluffy.Page` for `switch_page`.
- Use bang functions inside the callback so failures stop the test.
- Do not natively close the page or context, call `remove_all_listeners`, `set_default_timeout`, `set_default_navigation_timeout` or `set_content`, stop tracing, or pass `no_wait_after:` or `signal:`. Those break Fluffy's tracking.
- In a LiveView callback, do not consume `assert_patch` or `assert_redirect`; assert the resulting page after `unwrap`.

## Debugging

- Element actions fail with `Fluffy.OperationError`, whose `cause` holds the driver's error. Failed assertions are `ExUnit.AssertionError`.
- Traces, screenshots and videos are PlaywrightEx.Test's: `config :playwright_ex, :test, trace: :retain_on_failure, screenshot: :only_on_failure`, or a tag such as `@tag trace: true`. A failed test gets `error-context.md` in its `test-results/` dir. `Fluffy.Playwright.step/4` names a step of the test in its trace (Playwright only). `Fluffy.open_browser/1` opens the current page on any driver.
