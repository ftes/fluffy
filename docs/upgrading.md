# Upgrading to 0.9

To upgrade a 0.8 suite to 0.9, switch to the pinned Playwright 1.65 driver and check
the API and behavior changes below. See the [changelog](../CHANGELOG.md) for details.

From an earlier release, also read the changelog up to 0.8. The 0.8 change most likely
to bite: LiveView sessions see the root layout and portal content, so a locator that
matched once can now match twice.

## Setup

- Install the pinned driver and a browser with `mix playwright.install chromium`.
  Drop the npm `playwright` package and the `assets_dir` config; you no longer install
  Node.js or npm yourself, as the install task fetches a pinned Node.js with the driver.
  `executable:` now takes a Playwright 1.65 CLI such as `node_modules/.bin/playwright`,
  not `cli.js`; usually drop it and let Playwright install the driver.
- Replace the CI browser install too: use `mix playwright.install chromium --with-deps`
  on Linux runners. For Microsoft's Playwright image or a system browser, follow
  [Troubleshooting](installation.md#troubleshooting).
- Prefer `only: [:dev, :test]` to `only: :test`, so Playwright's Mix tasks and
  `mix usage_rules.sync` work in `:dev`, and widen the `lazy_html` line `phx.new`
  generates to match. List Playwright too for its usage rules; see
  [Usage rules for coding agents](installation.md#usage-rules-for-coding-agents).

  Use the [current Fluffy dependency entry](installation.md#elixir-dependency)
  in place of the 0.8 requirement.
- Fluffy requires Phoenix 1.7.10 or later and LiveView 1.1.32 or later; LiveView 1.0 is no
  longer supported. Upgrade them first, raising your requirements where they hold an
  older version back.
- PlaywrightEx is renamed `Playwright` (app `:playwright`, modules `Playwright.*`; the Hex
  package stays `playwright_ex`). If you list it, replace `{:playwright_ex, ...}` with the
  line from [Usage rules for coding agents](installation.md#usage-rules-for-coding-agents), where `hex: :playwright_ex`
  is required, rename `config :playwright_ex` to `config :playwright`, and run
  `mix deps.unlock --unused`. `alias Fluffy.Playwright` now shadows `Playwright.*`, so
  don't alias it where you call the dependency, such as in `@tag Playwright.Test.use(...)`.
- Playwright 1.65's own breaking changes apply: actions wait for an element to be not
  inert, cookie matching follows RFC 6265, and text the browser does not render is no
  longer part of accessible names.
- Browser console messages are no longer logged, as in Playwright, and `js_logger:`,
  custom loggers and `Fluffy.Playwright.ConsoleLogger` are gone. To log them, register
  a [console listener](installation.md#troubleshooting).
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
- Move browser settings from `config :fluffy, :playwright` to `config :playwright, :test`.
  Rename `engine:` to `browser_name:` and keep `launch_options:`. Set a custom CLI with `config :playwright, :driver,
  executable: ...` in `config/config.exs`. Drop `pool_size`: each test gets its browser
  from `Playwright.Test.BrowserPool.browser/1`, up to [`workers`](`e:playwright:test-artifacts.md#workers`) at once.
- `browser_context:`, `launch_options:` and the options of `storage_state` and cookies
  pass through to Playwright, which rejects unknown ones. Page screenshots
  validate their options as element screenshots do: `mask:` takes Fluffy locators
  and `timeout: :once` raises.

## Timeouts

- `config :fluffy` is validated at startup: an unknown key, or the config of a module that
  doesn't exist, raises. Remove `playwright: false`, which does nothing.
- Remove `start_session(timeout:)` and split the old suite timeout by backend:

  ```diff
  -config :fluffy, timeout: 2_000, playwright: [timeout: 15_000]
  +config :fluffy, phoenix_backend_timeout: 2_000
  +config :playwright, :test, action_timeout: 15_000, navigation_timeout: 15_000, expect: [timeout: 5_000]
  ```

  The Phoenix default is 1 s. Without an action or navigation timeout, browser actions
  and navigations are bounded only by the test's timeout.
- `config :fluffy, base_url:` is removed: set Playwright's `base_url`
  ([Configuration](installation.md#configuration)).
- In native Fluffy calls, replace `timeout: 0` with `timeout: :once`; `0` now raises, as it
  means no timeout in Playwright. `Fluffy.PhoenixTest` facade calls keep `0`. For no limit,
  pass `:infinity`. Playwright actions, waits, `reload`, `go_back` and `go_forward` raise
  `ArgumentError` for `:once` instead of timing out after 1ms; pass a positive timeout.
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
- Replace `Fluffy.HTTPEvent` with `Playwright.Request` or `Playwright.Response`.
  Dialog, console, page error, frame, worker and WebSocket events also deliver their
  native Playwright values. Read them with functions such as
  `Playwright.Response.status/1` and `Playwright.Dialog.accept!/1`, and turn their
  page into a `Fluffy.Page` with `Fluffy.Playwright.page/2`.
- `Fluffy.Download`'s `read!` and `save_as!` are `read` and `save_as`. Only the
  documented fields of `Fluffy.Download` remain public.
- `page_status`, `page_to_have_status` and `Fluffy.Page.status` are removed, as in
  Playwright; on Playwright, assert on `Fluffy.Event.response/1` instead.
- Replace `setup context do Fluffy.Test.setup(context) end` with `use Playwright.Test`
  after `ConnCase`, directly or in your case template. Starting a session outside a
  registered test raises, including for Phoenix-only and facade suites.
- Replace `Fluffy.Playwright.trace/2`, `artifact_dir` and `trace_dir` with Playwright Test's
  artifact settings. For the suite, use `config :playwright, :test, trace: :retain_on_failure,
  screenshot: :only_on_failure`. For a module, use `use Playwright.Test, trace: :on`;
  for a describe use `@describetag Playwright.Test.use(trace: :on)`, and for a test
  use `@tag Playwright.Test.use(trace: :on)`.
  `screenshot:` and `video:` work the same way. Artifacts go to `test-results/<test>/`;
  failed operations no longer write HTML or error text.
- Fluffy no longer starts or adopts Ecto sandbox owners: keep the generated DataCase
  setup (`Sandbox.start_owner!(repo, shared: not tags[:async])` and `stop_owner` in
  `on_exit`) and use it before `use Playwright.Test`. Drop `sandbox: false` and `repos:`;
  Fluffy adds the metadata of `config :fluffy, ecto_repos:` to browser sessions. A plain
  `Sandbox.checkout` in the test process does not work for browser tests. An app that keeps its
  own LiveView sandbox hook passes `Fluffy.Sandbox` there, and starts its session with Fluffy, so
  the test waits for those LiveViews to exit
  ([Keeping your own LiveView hook](installation.md#keeping-your-own-liveview-hook)).
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
  Replace `page_url(path: "/potions")` with `page_path("/potions")` in `Fluffy.Assert`.
  Use `page_path("/potions", params: %{state: "brewing"})` for a flat query subset,
  or a `page_url` regex or predicate for raw queries and fragments.
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
- `Fluffy.PhoenixTest` takes and returns a plain `Fluffy.Session`, and
  `Fluffy.PhoenixTest.Session` is removed: replace `facade.session` with the session itself,
  and a match on `%Fluffy.PhoenixTest.Session{}` with `%Fluffy.Session{}`. Drop helpers
  that only unwrap and rewrap the session around native calls. Native locators still
  need explicit scoping inside a facade `within`.

## Workarounds that can go

Most `unwrap` callbacks that called Playwright with the handle's `frame_id`,
`context_id` or `page_id` have a Fluffy function now. Replace them rather than port them:

- `add_init_script`: `Fluffy.Playwright.add_init_script/3`.
- `Frame.wait_for_function` with `is_function:` and `arg:`:
  `Fluffy.Playwright.wait_for_function(session, expression, arg)`.
- An `evaluate` of `document.querySelector(...)` that reads text or an attribute, say a
  `dataset`: `Fluffy.text_content(session, locator)` or
  `Fluffy.get_attribute(session, locator, "data-state")`, which work on Phoenix too. For
  other JavaScript on an element, `Fluffy.Playwright.evaluate(session, locator, expression)`.
- `Frame.expect(expression: "to.be.in.viewport")`: `|> assert(in_viewport(locator))`.
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
`by_role(:navigation)`, and a named `<section>` is `by_role(:region, "...")`.

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
- Use `to_have_value` on an input, textarea, select or its label. For other elements,
  assert their text or `value` attribute instead.
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
  fails; use `assert_has("input#flag", value: "true")`, which adds no visibility
  requirement.
- The facade's `count:` and `at:` count visible matches only, as PhoenixTest.Playwright
  did, so `assert_has("input[type=hidden]", count: 1)` now fails. Check DOM presence with
  a native count: `assert(session, count(by_css("input[type=hidden]"), 1))`.
- On Static and LiveView the options of a dropdown `<select>` are now hidden, as on
  Playwright, so `assert_has("#house option", text: "Ravenclaw")`,
  `assert_has("option[selected]", ...)` and native visibility assertions on them fail. Check the
  selection with the facade's `assert_has("#house", selected: "Ravenclaw")` or
  `by_role(:option, selected: true)`, and count options natively
  ([Selects and options](actions.md#selects-and-options)).
- Text matching skips `<script>` and `<style>`, as in Playwright, even as the matched
  element, so `assert_has("script", text: "...")` fails. Match attributes with a native
  count (`assert(session, count(by_css("script[nonce]"), 1))`), or read the text
  with `Fluffy.text_content(session, by_css("script#data"))`, on every driver.
- `select_option` with `[]` deselects every option, and a list mixing values with
  option maps raises. The `values` assertion requires a multiple select.
- The facade's `click_button` no longer matches `<input type="file">`.
- LiveView `set_input_files` raises unless the upload's form has an id.
- A `phx-trigger-action` form is submitted from mount or a pushed render, as LiveView's
  client does, and a link, form or redirect to another origin ends at a page with that URL
  ([Leaving the app](capabilities.md#leaving-the-app)) instead of raising. A test that
  asserted on the page before such a navigation, say a flash shown on the way to a sign-in
  provider, now ends at the target: assert where the app sent it with `page_url`,
  and the flash in a controller or LiveView test.

Rarer differences follow the browser too: some implicit roles and accessible names
changed, text in `<template>` no longer matches text locators, controls inside
`<noscript>` are not submitted, `press` raises in layout content without key
bindings, and a render resets local field state only in the views it changed. See the [changelog](../CHANGELOG.md) for the full list.
