# Upgrading to 0.9

Fluffy 0.9 runs on Playwright (Hex package `playwright_ex`), a port of the official
Playwright client with a pinned Playwright 1.65 driver. It follows Playwright more closely, and its Phoenix
drivers follow LiveView's client. This guide lists what a 0.8 suite must change, as one
step from 0.8; the [changelog](../CHANGELOG.md) has the details.

From an earlier release, also read the changelog up to 0.8. The 0.8 change most likely
to bite: LiveView sessions see the root layout and portal content, so a locator that
matched once can now match twice.

## Setup

- Install the pinned driver and a browser with `mix playwright.install chromium`.
  Drop the npm `playwright` package and the `assets_dir` config; Node.js is no longer
  needed. `executable:` now takes a Playwright 1.65 CLI such as
  `node_modules/.bin/playwright`, not `cli.js`; usually drop it and let Playwright
  install the driver.
- Run the install in CI too, as `mix playwright.install chromium --with-deps` on Linux
  runners; the driver would install itself in the first browser test, but browsers do
  not; see
  [GitHub Actions](`e:playwright:debugging-and-ci.md#github-actions`). In Microsoft's
  Playwright image, whose tag must match `Playwright.Driver.version/0`, `--no-browsers`
  is enough: the driver finds the image's browsers. For a system browser, as on Nix, pass
  `--no-browsers` and set `launch_options: [executable_path: ...]` or `channel:`; see
  [Playwright setup](installation.md#playwright-setup).
- Prefer `only: [:dev, :test]` to `only: :test`, so Playwright's Mix tasks and
  `mix usage_rules.sync` work in `:dev`, and widen the `lazy_html` line `phx.new`
  generates to match. List Playwright too for its usage rules; see
  [Elixir dependency](installation.md#elixir-dependency).

  ```diff
  -    {:lazy_html, ">= 0.1.0", only: :test},
  -    {:fluffy, "~> 0.8.0", only: :test}
  +    {:lazy_html, ">= 0.1.0", only: [:dev, :test]},
  +    {:fluffy, "~> 0.9.0", only: [:dev, :test]}
  ```
- Fluffy requires Phoenix 1.7.24 or later and LiveView 1.2.10 or later; LiveView 1.0 and 1.1
  are no longer supported. Upgrade them first, raising your requirements where they hold an
  older version back.
- PlaywrightEx is renamed `Playwright` (app `:playwright`, modules `Playwright.*`; the Hex
  package stays `playwright_ex`). If you list it, replace `{:playwright_ex, ...}` with the
  line from [Elixir dependency](installation.md#elixir-dependency), where `hex: :playwright_ex`
  is required, rename `config :playwright_ex` to `config :playwright`, and run
  `mix deps.unlock --unused`. `alias Fluffy.Playwright` now shadows `Playwright.*`, so
  don't alias it where you call the dependency, such as in `@tag Playwright.Test.use(...)`.
- Playwright 1.65's own breaking changes apply: actions wait for an element to be not
  inert, cookie matching follows RFC 6265, and text the browser does not render is no
  longer part of accessible names.
- Browser console messages are no longer logged, as in Playwright, and `js_logger:`,
  custom loggers and `Fluffy.Playwright.ConsoleLogger` are gone. To log them, register
  a listener: `on(session, Event.console(), &Logger.info(Playwright.ConsoleMessage.text(&1)))`.
- Browser sessions use Playwright's `en-US` locale instead of `en`, and Phoenix sessions,
  which sent no Accept-Language before, now send the test's `locale` (`en-US` by default)
  unless a `conn:` sets its own. An app that picks its language from the request can render
  another one in Phoenix tests: set the one you expect with `use Playwright.Test, locale: ...`,
  or for one test with `@tag Playwright.Test.use(locale: ...)` ([Configuration](installation.md#configuration)).
- `start_session`'s `headers: [{name, value}]` is now `extra_http_headers: %{name => value}`,
  which replaces the test's `extra_http_headers` as in Playwright instead of merging into them.
  `base_url` and `extra_http_headers` in `browser_context:` raise: pass them to the session.
- The default base URL is the endpoint's `url` host on its listener's port, not the
  listener's address: `http://localhost:4002` with `phx.new`'s config, not
  `http://127.0.0.1:4002`. Drop a `check_origin: false` added for browser tests. If the
  browser can't reach the `url` host, set one it can in `config/test.exs`, or Playwright's
  `base_url` ([Configuration](installation.md#configuration)).
- Browser launch gets Playwright's 3-minute default instead of `timeout:`. A
  `launch_options: [timeout: ...]` that raised the limit on 0.8 now shortens it and can
  fail a loaded machine with `browserType.launch: Timeout ... exceeded`, so drop it.
- `browser_context:`, `launch_options:` and the options of `storage_state` and cookies
  pass through to Playwright, which rejects unknown ones. Page screenshots
  validate their options as element screenshots do: `mask:` takes Fluffy locators
  and `timeout: 0` raises.

## Timeouts

A browser session's timeouts follow Playwright Test and a Phoenix session's
`config :fluffy, phoenix_backend_timeout:`; `timeout:` follows Elixir: `0` checks once and
`:infinity` means no limit; see [Configuration](installation.md#configuration).

- `config :fluffy` is validated at startup: an unknown key, or the config of a module that
  doesn't exist, raises. Remove `playwright: false`, which does nothing.
- `start_session(timeout:)`, `config :fluffy, timeout:` and `config :fluffy, :playwright`
  are removed; the old config raises at startup. Set Playwright Test's defaults instead, in
  Playwright's config for the whole suite:

  ```diff
  -config :fluffy, timeout: 2_000, playwright: [timeout: 15_000]
  +config :playwright, :test, action_timeout: 15_000, navigation_timeout: 15_000
  +config :playwright, :expect, timeout: 5_000
  ```

  These are browser sessions'. Without them, browser actions and navigations have no timeout,
  so the test's timeout bounds them.
- `config :fluffy, base_url:` is removed: set Playwright's `base_url`
  ([Configuration](installation.md#configuration)).
- Playwright actions, waits, `reload`, `go_back` and `go_forward` raise `ArgumentError`
  for `timeout: 0` instead of timing out after 1ms; pass a positive timeout. Assertions
  and Phoenix actions still check once.
- For no limit, pass `timeout: :infinity`, never Playwright's `0`.
- Calls that have no timeout in Playwright take no `timeout:`: `Fluffy.Playwright.evaluate`
  and `storage_state`, and `Fluffy.cookies` and `clear_cookies`. Download `read` and `save_as` no longer
  end at a timeout; an unfinished download waits until the test times out.

## Renamed and removed APIs

- `Fluffy.unwrap/2` passes a `%Playwright.Page{}` on Playwright instead of a
  `Fluffy.Playwright.Handle`, which is removed. The new `Fluffy.unwrap_and_return/2`
  returns the callback's result.
- `Fluffy.Playwright.evaluate(session, expression, arg)` replaces the `is_function:`
  and `arg:` options. JavaScript `null` returns `:null`.
- `add_cookies`, `cookies` and `clear_cookies` move from `Fluffy.Playwright` to `Fluffy`,
  and work on Phoenix sessions too: `Fluffy.Playwright.add_cookies(session, cookies)` becomes
  `Fluffy.add_cookies(session, cookies)`. `cookies(session, urls)` takes the URL list. Cookie
  maps use Playwright's camelCase keys (`httpOnly:`, `sameSite:`, `partitionKey:`). A snake_case
  one such as `http_only:` raises. And `storage_state/2` returns atom keys:
  `state["cookies"]` becomes `state.cookies`.
- `Fluffy.HTTPEvent` is gone: request and response events deliver a
  `Playwright.Request` and `Playwright.Response`, as do the other browser events
  (dialog, console, page error, frame, worker and WebSocket) their Playwright values,
  as in Playwright. Read them with Playwright's functions, such as
  `Playwright.Response.status/1` and `Playwright.Dialog.accept!/1`, and turn their
  page into a `Fluffy.Page` with `Fluffy.Playwright.page/2`.
- `Fluffy.Download`'s `read!` and `save_as!` are `read` and `save_as`. Only the
  documented fields of `Fluffy.Download` remain public.
- `page_status`, `page_to_have_status` and `Fluffy.Page.status` are removed, as in
  Playwright; on Playwright, assert on `Fluffy.Event.response/1` instead.
- Configure the browser with `config :playwright, :test, browser_name: ..., launch_options:
  ...` (`config :playwright, :driver, executable: ...` in `config/config.exs` for a CLI)
  instead of `config :fluffy, :playwright`, which is removed. `pool_size` goes too: each
  test takes its own browser from `Playwright.Test.BrowserPool.browser/1`, at most `workers`
  at once
  ([Workers](`e:playwright:test-artifacts.md#workers`)).
- `Fluffy.Playwright.trace/2`, `artifact_dir` and `trace_dir` are removed. Traces,
  screenshots and videos come from `Playwright.Test`: set
  `config :playwright, :test, trace: :retain_on_failure, screenshot: :only_on_failure`
  and replace `setup context do Fluffy.Test.setup(context) end` with `use Playwright.Test` after
  your `ConnCase` (or in your case template, see `Playwright.Test`);
  record a module with `use Playwright.Test, trace: :on` and a describe block or test with `@tag Playwright.Test.use(trace: :on)` (or `screenshot:`, `video:`). Files go to
  `test-results/<test>/`; a failed operation no longer writes HTML or the error text.
- Fluffy no longer starts or adopts Ecto sandbox owners: keep the generated DataCase
  setup (`Sandbox.start_owner!(repo, shared: not tags[:async])` and `stop_owner` in
  `on_exit`) and use it before `use Playwright.Test`. Drop `sandbox: false` and `repos:`;
  Fluffy adds the metadata of `config :fluffy, ecto_repos:` to browser sessions. A plain
  `Sandbox.checkout` in the test process does not work for browser tests.
- `Fluffy.Playwright.screenshot` and `pdf` return the image or PDF, as in Playwright,
  instead of the session; the path is the optional `path:`:
  `screenshot(session, path)` becomes `screenshot(session, path: path)`,
  `screenshot(session, locator, path, options)` becomes
  `screenshot(session, locator, [path: path] ++ options)` and `pdf(session, path)` becomes
  `pdf(session, path: path)`.
- `by_test_id/2` takes no `attribute:`, as Playwright's `getByTestId`: every driver reads
  `config :playwright, :test, test_id_attribute:` (`data-testid` by default). For another
  attribute in one place, replace `by_test_id("hedwig", attribute: "data-owl")` with
  `by_css("[data-owl=\"hedwig\"]")`.
- `filter/2` takes no `exact:`, as in Playwright. Match a whole text with a regex, such as
  `filter(has_text: ~r/^Pro$/)`, which works on every driver.
- `page_url`/`page_to_have_url` and `Fluffy.Playwright.route/4` take URLs as Playwright
  does: a string, a regex or a predicate, which gets a `%URI{}` as before.
  Replace `page_url(path: "/potions")` with `page_url("/potions")` when the URL has no
  query, or with `page_url(&(&1.path == "/potions"))`; the `query:` and
  `fragment:` forms become a regex or a predicate too.
- A regex is a JavaScript `RegExp` on every driver: PCRE-only syntax such as `\A`, `\z`,
  `(?i)` or the `x` modifier raises `ArgumentError` on Static and LiveView too. Use `^`, `$`
  and the `i` modifier, or a `Playwright.RegExp` for JavaScript-only syntax.
- The `Fluffy.Expect.checked_option` type is `to_be_checked_option`.
  `Fluffy.Locator.describe`, `new` and `append` are internal; `inspect/1` renders a locator.
- A failed navigation raises `Fluffy.OperationError` instead of a `RuntimeError` on both
  backends. Its `cause` is Playwright's exception, as for a failed action, or a message
  from Fluffy: a Phoenix visit that was aborted or redirected too often, a LiveView that
  did not connect, or a page that did not respond to Fluffy's document check.
- A LiveView that exits during a Phoenix operation raises `Fluffy.OperationError` with a
  `Fluffy.LiveViewError` as its `cause`; rescue the `OperationError`.
- `Fluffy.CapabilityError.capability` is an id of `Fluffy.Capability.matrix/0`, and the
  call is in `operation`: match `capability: :browser_pointer_typing, operation: :hover`
  where you matched `capability: :hover`. `go_back` and `go_forward` on Phoenix raise
  `capability: :browser_history` instead of `:pages`.
- `Fluffy.Capability.matrix_version/0`, the `:experimental` status and the matrix's
  Playwright column are removed: `Fluffy.Capability.status/2` takes `:static` or `:live`,
  not `:playwright`.
- `browser:` and `browser_context:` on a Phoenix session and `conn:` on a Playwright one
  raise `Fluffy.CapabilityError` instead of `ArgumentError`.
- Before a Phoenix session's first `visit`, page operations (actions, expectations,
  `reload`, `unwrap`, `open_browser`) raise `ArgumentError` instead of mostly
  `FunctionClauseError`.

## Workarounds that can go

Most `unwrap` callbacks that called Playwright with the handle's `frame_id`,
`context_id` or `page_id` have a Fluffy function now. Replace them rather than port them:

- `add_init_script`: `Fluffy.Playwright.add_init_script/3`.
- `Frame.wait_for_function` with `is_function:` and `arg:`:
  `Fluffy.Playwright.wait_for_function(session, expression, arg)`.
- An `evaluate` of `document.querySelector(...)`, say to read a `dataset`:
  `Fluffy.Playwright.evaluate(session, locator, "el => el.dataset.state")`.
- `Frame.expect(expression: "to.be.in.viewport")`: `Fluffy.Assert.in_viewport/2` or
  `Fluffy.Expect.to_be_in_viewport/2`.
- `Page.route`: `Fluffy.Playwright.route/4`, whose handler gets the `Playwright.Route`.
- `BrowserContext.clock_install` and `clock_fast_forward`:
  `Fluffy.Playwright.Clock.install/2` and `fast_forward/3`.
- `Frame.press`: `Fluffy.press/4`, which takes any Playwright key.
- A click at a position, mouse moves or a bounding box: `click(session, locator,
  position: %{x: 5, y: 5})`, `Fluffy.Playwright.Mouse` and
  `Fluffy.Playwright.bounding_box/3`.
- `Frame.is_checked`, then a click on the label of a hidden input:
  `Fluffy.set_checked(session, by_css("label[for=terms]"), true)`. As in Playwright, the
  label stands for its input.

The other callbacks get a `%Playwright.Page{}`; Playwright's
[changelog](`e:playwright:changelog.md`) lists its 1.65 breaking changes.

On Phoenix, `by_role` knows the landmark roles, so a `by_css("nav")` stand-in becomes
`by_role(:navigation)`, and a named `<section>` is `by_role(:region, name: "...")`.

## Phoenix behavior

The Phoenix drivers now act like a browser running LiveView's client, so some tests
that passed on 0.8 act differently:

- `click` sends the closest `phx-click`, the target's or an ancestor's, then takes the
  default action of the closest button, link or label: it submits the form, follows the
  link, or clicks the label's control, toggling a checkbox and sending the control's
  `phx-click` and `phx-change`. On 0.8 it sent only the target's own `phx-click`, like
  `render_click`, and a click on text inside a button, link or label did nothing. A
  click inside a LiveView link patches or navigates, even past a closer `phx-click`, and
  `href="#"` has no default action.
- As in Playwright, a label takes its control's enabled state, so `to_be_enabled` and
  `to_be_disabled` on a label follow its control, and `check` and `uncheck` on a label
  click the label, sending its `phx-click` too.
- As in Playwright, `disabled` only disables native form controls, so a `disabled` link
  or `div` is clickable, while text inside a disabled button is disabled too.
- Events carry what the browser sends: the form's current serialization, so an
  unchecked checkbox no longer sends its rendered value, a control's current `value`,
  and a `JS.push` `target:`. Clicking a checkbox or radio also sends its form's
  `phx-change`.
- `by_role` follows Playwright's role and name rules. Landmarks, lists, list items and
  dialogs no longer take a name from their content: name them with `aria-label` or
  `aria-labelledby`.
- Chained locators, `filter(has:)` and `within/3` search descendants only, so they no
  longer match their scope element; `by_text` under a parent still matches the parent,
  as on Playwright.
- Visibility ignores `aria-hidden`, as in Playwright, while `<input type="hidden">`,
  descendants of `hidden`, `<title>`, `<script>`, `<template>` and similar content count
  as hidden. So a facade `assert_has("input#flag[value='true']")` on a hidden input
  fails; use `assert_has("input#flag", value: "true")` or `count: 1`, which add no
  visibility requirement.
- Text matching skips `<script>` and `<style>`, as in Playwright, even as the matched
  element, so `assert_has("script", text: "...")` fails even with `count:`. Match
  attributes with `count:` (`assert_has("script[nonce]", count: 1)`), or read the text
  natively: on Static, `unwrap` passes the `Plug.Conn`, so check `conn.resp_body`; on
  Playwright, use `Fluffy.Playwright.evaluate(session, by_css("script#data"),
  "el => el.textContent")`. On LiveView, `unwrap` passes the view, whose
  `Phoenix.LiveViewTest.render/1` covers the LiveView's markup but not the layout.
- `select_option` with `[]` deselects every option, and a list mixing values with
  option maps raises. `to_have_values` requires a multiple select.
- The facade's `click_button` no longer matches `<input type="file">`.
- LiveView `set_input_files` raises unless the upload's form has an id.

Rarer differences follow the browser too: some implicit roles and accessible names
changed, text in `<template>` no longer matches text locators, controls inside
`<noscript>` are not submitted, `press` raises in layout content without key
bindings, and a render resets local field state only in the views it changed. See the [changelog](../CHANGELOG.md) for the full list.
