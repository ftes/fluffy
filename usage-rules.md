# Fluffy usage rules

Fluffy runs Phoenix feature tests through one Playwright-shaped API, in-process or in a real browser. These rules build on Playwright's (sync both as one skill, see "Usage rules for coding agents" in `docs/installation.md`) and cover only what differs. Read the guides before relying on a feature: `mix usage_rules.docs Fluffy` or hexdocs.pm/fluffy.

## Where Fluffy differs from Playwright's rules

- `timeout: 0` checks once, as in Elixir, and Playwright actions reject it; `:infinity` is no limit.
- Start sessions, not `Playwright.Case`'s `page` and `context`: `use Playwright.Test` (never `Playwright.Case` or `Fluffy.Case`) in every module that starts one, Phoenix or browser, after the app's `ConnCase` (before it, the `test/3` imports clash). It adds no imports, session or `Test` alias: start the session in a setup, e.g. `%{session: start_session(ctx[:backend] || :phoenix)}`, and tag with `@tag Playwright.Test.use(...)` in full.
- Assert with Fluffy's assertions, not raw `Playwright.Expect` matchers, and don't call `set_default_timeout` or `set_default_navigation_timeout`: Fluffy owns the page. Retry app state or a block of Fluffy calls with `assert(poll(fun, assertion))` and `assert(pass(fun))` in a pipeline, `Playwright.Expect.poll!/3` and `to_pass!/2` outside one; inside a retried block, give assertions `timeout: 0`.
- Never test a JavaScript value by truthiness in Elixir: `null` and `NaN` arrive as `:null` and `:nan`, and they, `0` and `""` are truthy in Elixir, so `assert(value)` or a `poll` assertion `&assert(&1)` passes on them. Compare explicitly (`&assert(&1 == "playing")`), or keep the condition in JavaScript with `Fluffy.Playwright.wait_for_function/3`.
- `use Fluffy.Assert` goes after `use Playwright.Test`, else `assert/2` is ambiguous. Check visibility with `assert_has(locator)` and `refute_has(locator)`, not `assert(visible(locator))`.
- Phoenix sessions time out after `config :fluffy, phoenix_backend_timeout:` (1 s), not Playwright Test's timeouts.
- In a case template, `use Playwright.Test, unquote(opts)` goes in `using opts`; if the template's own `setup` starts the session, also add a bare `use Playwright.Test` after `use ExUnit.CaseTemplate` ([Shared test case](docs/usage.md#shared-test-case)).
- Playwright's alias trap covers `alias Fluffy.Playwright` too: where a module uses the dependency's modules, write `Fluffy.Playwright.evaluate(...)` in full or alias it `as: FluffyPlaywright`.

## Choosing an API and a backend

- Write new tests, and migrate PhoenixTest.Playwright suites, on the native API: `import Fluffy`, `import Fluffy.Locator`, `use Fluffy.Assert`. Use the PhoenixTest-style facade, `import Fluffy.PhoenixTest`, only when the user wants a minimal-diff PhoenixTest port; keep native calls in it to a few (a test that needs more goes on the native API), and never import it alongside `import Fluffy`.
- `start_session(:phoenix)` is the default; it picks the Static or LiveView driver per page. Use `:playwright` for JavaScript, layout and computed style, native validation, dialogs, network events, tabs or focus. Fluffy reads no test tags: pick the backend in your setup.
- Check `docs/capabilities.md` before relying on browser behavior in a Phoenix test: what a backend can't do raises `Fluffy.CapabilityError`. LiveView ignores `phx-debounce`/`phx-throttle`, and Phoenix ignores `data-confirm`.
- Phoenix checks structural visibility (`hidden`, `type="hidden"`), not CSS; test rendered visibility on `:playwright`.

## Coming from LiveViewTest, ConnTest or PhoenixTest

- Phoenix's "LiveView tests" rules don't apply to feature tests: fill and click as users do, assert the text they see, and reach `Phoenix.LiveViewTest` only through `unwrap`.
- No `render_async`, `follow_redirect`, `assert_redirect` or `assert_patch`: LiveView actions and assertions retry and Fluffy follows navigation, so assert the resulting page (`page_url("/creatures")`). Static checks once.
- Upload with `set_input_files`, also on a `live_file_input`.
- Don't assert `.phx-connected`: a Playwright `visit` waits for LiveViews to connect.
- There is no page status assertion; on Playwright, use `Event.response`.
- Keep the ids Phoenix templates need, but locate by them only before adding a test id. Fluffy's `by_role`, `by_label`, `by_text`, `by_test_id`, ... are Playwright's `get_by_*`; scope with the parent first, `by_role(parent, :row, name: "x")`. For buttons and links, `import Fluffy.Locator.Roles` and write `button("Save")` and `link("Home")` for `by_role(:button, name: "Save")` and `by_role(:link, name: "Home")`; scope with `by_role(parent, :link, name: "Home")`.
- Hidden inputs fail `visible`, a plain facade `assert_has` and role locators. Assert them without visibility: `assert(value(by_css("#token"), "x"))`, `assert(count(by_css("#token"), 1))`. For a checkbox hidden behind its label, `set_checked` the label.
- The app's `DataCase`/`ConnCase` owns the Ecto sandbox (`Sandbox.start_owner!`) before the session starts; a plain `Sandbox.checkout` doesn't work for browser tests.

## Fluffy's own API

- To use a page value, read it on any driver with `text_content`, `get_attribute`, `input_value` or `title`, not `evaluate`, and `all` for a locator per match; check values with assertions, which retry. `wait_for(session, locator, state: :hidden)` works on every driver too.
- Events: `pending = wait_for(session, Event.download())`, act, `await(pending)`, or `assert_event` in a pipeline. Downloads work on every driver, other events on Playwright.
- A `Fluffy.Playwright.route/4` handler answers each request once and must not block: hand database work to a `Task` (it keeps the sandbox) and fulfil from there.
- `Fluffy.unwrap/2` passes the driver's native value (`Plug.Conn`, `LiveViewTest.View`, `Playwright.Page`). In it, don't close the page or context, remove listeners, `set_content`, stop tracing, pass `no_wait_after:` or `signal:`, or consume `assert_patch`: that breaks Fluffy's tracking.
- Actions fail with `Fluffy.OperationError` (the driver's error is its `cause`). `Fluffy.step/3` names a trace step and `Fluffy.open_browser/1` opens the current page, on any driver.
