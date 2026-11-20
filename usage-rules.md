# Fluffy usage rules

Fluffy runs Phoenix feature tests through one Playwright-shaped API, in-process or in a real browser. It is a dev and test dependency (`only: [:dev, :test]`), never in production; a `lazy_html` the app lists `only: :test` must widen to match.

## Setup

- Sync Playwright's usage rules too: list `{:playwright, "~> 1.65.0-rc.3", hex: :playwright_ex, only: [:dev, :test]}` and sync both as one composed `phoenix-feature-tests` skill of `[:fluffy, :playwright]` (`docs/installation.md`, "Usage rules for coding agents"). Fluffy's rules build on them and win where they differ: take the `:playwright` locator, waiting and event advice, but not its Setup, per-context timeouts (`set_default_timeout`) or raw `Playwright.Expect` matchers, which Fluffy's sessions and assertions replace (its `poll!` and `to_pass!` stay).
- `config :fluffy, endpoint: MyAppWeb.Endpoint` in `config/test.exs`. With Ecto, also `config :fluffy, ecto_repos: [MyApp.Repo]` and the sandbox plug and mount hook from `docs/installation.md`, behind an `Application.compile_env` flag set in `config/test.exs` because Fluffy is not in production. The app's DataCase/ConnCase owns the sandbox (`Sandbox.start_owner!` and `stop_owner` in `on_exit`), used before `use Playwright.Test`; Fluffy only sends its metadata from browser sessions. A plain `Sandbox.checkout` does not work for browser tests.
- Add `use Playwright.Test` after the app's `ConnCase` (never before it: the `test/3` imports clash), in every test module that starts a session, Phoenix-only or browser: every session needs a registered test, and raises without one. Never write `use Fluffy.Case` (removed) or `use Playwright.Case`. The "Testing with Playwright.Test" section of the `:playwright` usage rules applies (browser pool, timeouts, artifacts, `step`, snapshots, case templates), but start Fluffy sessions instead of using its `browser`, `context` and `page`. It only registers the test: sessions can start, and an operation that outlasts the test fails with Fluffy's error at the test timeout. It adds no imports and no session: add your own imports (see below) and a setup such as `setup ctx do %{session: start_session(ctx[:backend] || :phoenix)} end`, where the tag is yours. It takes `use Playwright.Test`'s options for the module, such as `trace:`, `screenshot:`, `video:` and context options like `locale:` (`use Playwright.Test, trace: :on`); for a describe block or a test, tag it with `Playwright.Test.use/1`. Browser sessions take their timeouts from these options too; Phoenix sessions don't. In a case template, put `use Playwright.Test, unquote(opts)` in `using opts`; if the template's own `setup` starts a session, also put a bare `use Playwright.Test` right after `use ExUnit.CaseTemplate`, and start the sandbox before the session.
- Browser tests need `server: true` on the endpoint, `config :playwright, :test` for the browser (`browser_name`, `launch_options`) and `mix playwright.install chromium`. Sessions use the test's browser from `Playwright.Test.BrowserPool.browser()`, Playwright Test's worker: at most `workers` tests hold one at once, and a test without a Playwright session takes none; pass `browser:` for another, such as `BrowserPool.browser(launch_options: [headless: false])`. For a whole module, `use Playwright.Test, launch_options: [headless: false]` (or `@moduletag Playwright.Test.use(launch_options: ...)`) sets its browser, with no `browser:`; a describe's or test's `@tag` can't set browser options. For more users, start more sessions, each in its own browser context. For a remote Playwright server, set `connect_options: [ws_endpoint: ..., expose_network: "<loopback>"]`, so the browser reaches the app at `base_url`.
- The browser opens the endpoint's `url` host, such as `localhost`, on its listener's port, so Phoenix's default `check_origin` passes. Set `config :playwright, :test, base_url:` only when the browser reaches the app at another address.

## Choosing an API and a backend

- Native API: `import Fluffy`, `import Fluffy.Locator`, and `use Fluffy.Assert` (or `import Fluffy.Expect`). PhoenixTest-style facade: `import Fluffy.PhoenixTest` on its own, never alongside `import Fluffy`, whose names overlap. Follow what the suite already uses; a new suite defaults to `use Fluffy.Assert` (`docs/assertions.md` compares the two).
- A suite coming from PhoenixTest can keep the facade. Native calls accept the facade's `facade.session`.
- `start_session(:phoenix)` is the default choice. Its first visit picks the Static or LiveView driver, and later navigations pick again. There is nothing to select between those two.
- `start_session(:playwright)` is for JavaScript, computed style and layout, native validation, dialogs, network events, tabs or focus.
- In the facade, `conn |> visit(path)` always starts a Phoenix session; use `start_session(:playwright) |> visit(path)` for a browser.
- To start logged in on both backends, sign the session cookie in-process and pass it to `Fluffy.add_cookies/2` with `url: Fluffy.base_url(session)` before `visit` ([Logging in](docs/usage.md#logging-in)).
- To check accessibility, follow PlaywrightEx's axe-core recipe on a Playwright session with `Fluffy.Playwright.add_script_tag/2` and `Fluffy.Playwright.evaluate/2` ([Accessibility testing](docs/usage.md#accessibility-testing)).
- Fluffy reads no test tags. Pick a session's backend in your own setup, for example from your own `backend` tag.

```elixir
start_session(:phoenix)
|> visit("/creatures/new")
|> fill(by_label("Name"), "Basilisk")
|> click(by_role(:button, name: "Register"))
|> assert(visible(by_text("Creature registered")))
|> assert(page_url("/creatures"))
```

## Locators

- Choose locators as the "Locators and assertions" section of the `:playwright` usage rules says; Fluffy's `by_role`, `by_label`, `by_placeholder`, `by_text`, `by_alt_text`, `by_title` and `by_test_id` are its `get_by_*`.
- In a Fluffy suite, Phoenix's "LiveView tests" usage rules don't apply to feature tests: don't drive forms with `render_submit`/`render_change` or assert `has_element?` on element ids, and do assert the text users see. Fill and click as users do, and reach `Phoenix.LiveViewTest` only through `unwrap`. Their advice to test outcomes, not implementation details, still holds.
- Keep the DOM ids Phoenix templates give key elements (streams, hooks and forms need them), but don't locate by them first: an existing id (`by_css("#owl-form")`) is the fallback before adding a test id. `by_test_id(id)` takes no options: set the attribute with `config :playwright, :test, test_id_attribute: ...`, or use `by_css("[data-owl=\"hedwig\"]")` for another attribute.
- Text, role-name and label matching is substring by default; pass `exact: true` for a complete match.
- Locators are values. Scope with `by_role(parent, :row, name: "x")`, refine with `filter(has: ...)`, `first`, `last`, zero-based `nth`, `and_`, `or_`. Use `frame_locator` for iframes on Playwright.
- Native `visible` is strict like actions; assert `count(locator, n)` when several matches are intended. Facade `assert_has` accepts any visible match.

## Assertions and waiting

- LiveView retries actions and assertions until the timeout, as Playwright does, and Static checks immediately. So there is no `render_async`: assert what the async result shows.
- Fluffy follows redirects, `push_navigate` and patches itself. Instead of `follow_redirect`, `assert_redirect` or `assert_patch`, assert the resulting page, e.g. `page_url("/creatures")`.
- Upload with `set_input_files`, also on a `live_file_input`, not LiveViewTest's `file_input`/`render_upload`.
- Configuration ([installation guide](docs/installation.md#configuration)): Playwright Test owns the test's options, and `config :fluffy` has only `endpoint`, `ecto_repos`, `file_input_max_bytes` and `phoenix_backend_timeout`. Phoenix sessions use `phoenix_backend_timeout` (1 s); a `Playwright.Test.use` timeout tag doesn't apply there.
- `timeout: 0` checks once, unlike Playwright's no timeout; Playwright actions and waits reject it. For no timeout, pass `timeout: :infinity`, never Playwright's `0`.
- A Playwright `visit` already waits for LiveViews to connect, so do not assert `.phx-connected`.
- `use Fluffy.Assert` gives `assert(visible(l))` and `refute(visible(l))`, and ordinary ExUnit asserts still work. `import Fluffy.Expect` gives `expect(to_be_visible(l))` and `expect(not_(to_be_visible(l)))`. Both return the session.
- `refute(visible(l))` passes for an absent or invisible element. Use `assert(count(l, 0))` to require DOM absence.
- URL strings match the complete URL, including query and fragment. When only the path matters, use a regex or a predicate, which gets a `%URI{}`: `page_url(&(&1.path == "/x"))`.
- There is no page status assertion. On Playwright, assert on `Event.response` instead.
- To wait for a computed value or app state, use `Playwright.Expect.poll!/3`, and `Playwright.Expect.to_pass!/2` to retry a block of Fluffy calls, never a hand-rolled `evaluate`/`wait_for_function` loop or `Process.sleep`. `poll!` retries only the assertion, so return a value from its callback rather than raising. Give the assertions inside `to_pass!` `timeout: 0` so it does the retrying, and actions a short positive timeout (Playwright actions reject `0`), and on Static poll app state or `reload` in the callback: the page doesn't change between attempts ([Polling and retrying blocks](docs/assertions.md#polling-and-retrying-blocks)).
- Static and LiveView check structural visibility (`hidden`, `type="hidden"`) and do not compute CSS, so `display: none` alone counts as visible there. `aria-hidden="true"` does not affect visibility; only `by_role` excludes it. Use `:playwright` to test rendered visibility.
- Text matching skips `<script>` and `<style>`, as in Playwright, so `assert_has("script", text: ...)` fails even with `count:`. Match attributes with `count:`, or read the text with `text_content(session, by_css("script#data"))`.
- To use a page value in the test, read it on any driver: `text_content`, `get_attribute`, `input_value` and `all_text_contents` (`inner_text` and `all_inner_texts` in `Fluffy.Playwright`). Reads wait for the element but not for its value, so check values with assertions, which retry, not by comparing a read; don't use `Fluffy.Playwright.evaluate` or `unwrap_and_return` for them.

## Hidden inputs

- `visible` and a plain facade `assert_has` fail on hidden inputs and inside `hidden` elements, even with an attribute selector such as `input[value='x']`, and role locators exclude them. Assert with CSS, without a visibility requirement:
  - Facade: `assert_has("#token", count: 1)`, `assert_has("#token", value: "x")`, `assert_has("#terms", checked: true)`.
  - Native: `assert(count(by_css("#token"), 1))`, `assert(value(by_css("#token"), "x"))`, `assert(checked(by_css("#terms")))`.
- For a checkbox or radio hidden and styled through its label, `check(by_label("Terms"))` resolves to the input, which Playwright can't click as it is not visible. Target the label, as a user clicks it: `set_checked(session, by_css("label[for=terms]"), true)` works on every backend.

## Capabilities

- Check `docs/capabilities.md` before relying on a browser behavior in a Phoenix test. Fluffy raises `Fluffy.CapabilityError` (fields `capability`, a matrix id, `operation`, `backend`, `driver`, `detail`) for what a backend or driver cannot do, rather than ignoring it.
- Playwright-only helpers live in `Fluffy.Playwright` (`hover`, `drag_to`, `press_sequentially`, `evaluate`, `new_page`, `switch_page`, ...), `Fluffy.Playwright.Keyboard`, `Mouse` and `Clock`.
- Playwright-only options, such as `by_role(:button, pressed: true)` or `click(l, force: true)`, raise `Fluffy.CapabilityError` on Phoenix.
- LiveView ignores `phx-debounce` and `phx-throttle`. Phoenix `click` ignores `data-confirm`. `press` raises on Static and only forwards the key to bound handlers on LiveView.

## Events, downloads and routes

- Register before the action. `pending = wait_for(session, Event.download())`, act, then `await(pending)`, once. In a pipeline, `assert_event(Event.download(), &click(&1, button), fn download -> ... end)`, or `expect_event` with `Fluffy.Expect`.
- Downloads work on every driver: `Download.read/2`, `Download.save_as/2`. Other events require Playwright.
- `Fluffy.Playwright.route/4` registers before the request and hands the handler a `Playwright.Route`. Answer once with `Playwright.Route.fulfill!/2`, `continue!/2`, `abort!/2` or `fallback!/2`; an unanswered request hangs until its action times out. Don't block in a route handler (`receive`, `Process.sleep`, `GenServer` calls, database or Phoenix work); hand off to a `Task` and fulfil from it: `fn route -> Task.start(fn -> Route.fulfill!(route, json: Owlery.letters_for("Harry")) end) end`. The `Task` inherits `$callers`, so the Ecto sandbox works there.

## Dropping to Playwright

Prefer the shared API. For what it does not cover:

- `Fluffy.unwrap(session, fun)` passes a `%Plug.Conn{}` (Static, return the updated conn), `%Phoenix.LiveViewTest.View{}` (LiveView) or `%Playwright.Page{}` (Playwright), and returns the session. It raises on a Phoenix session before its first visit.
- `Fluffy.Playwright.unwrap(session, locator, fun)` passes the `%Playwright.Locator{}` for a Fluffy locator, resolved in the active page and through frame locators. A navigation it causes is adopted. It raises `Fluffy.CapabilityError` on Phoenix.
- Events other than page events, downloads and file choosers deliver Playwright's values: read a response with `Playwright.Response.status/1`, accept a dialog with `Playwright.Dialog.accept!/1`. `Fluffy.Playwright.page(session, native_page)` turns their page into a `Fluffy.Page` for `switch_page`.
- `alias Fluffy.Playwright` shadows the `Playwright` dependency: in that module, `Playwright.Page` means `Fluffy.Playwright.Page`, and `@tag Playwright.Test.use(...)` doesn't compile. Where a module uses the dependency's modules, don't alias `Fluffy.Playwright`; write `Fluffy.Playwright.evaluate(...)` in full.
- Do not natively close the page or context, call `remove_all_listeners`, `set_default_timeout`, `set_default_navigation_timeout` or `set_content`, stop tracing, or pass `no_wait_after:` or `signal:`. Those break Fluffy's tracking.
- In a LiveView callback, do not consume `assert_patch` or `assert_redirect`; assert the resulting page after `unwrap`.

## Debugging

- Element actions fail with `Fluffy.OperationError`, whose `cause` holds the driver's error. Failed assertions are `ExUnit.AssertionError`.
- Traces, screenshots and videos are Playwright.Test's: `config :playwright, :test, trace: :retain_on_failure, screenshot: :only_on_failure`, or a tag such as `@tag Playwright.Test.use(trace: :on)`. A failed test gets `error-context.md` in its `test-results/` dir. `Fluffy.step/3` names a step of the test in its trace, on any driver. `Fluffy.open_browser/1` opens the current page on any driver.
