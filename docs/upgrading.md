# Upgrading to 0.9

Fluffy 0.9 runs on PlaywrightEx 0.17, a port of the official Playwright client with
a pinned Playwright 1.65 driver. It follows Playwright more closely, and its Phoenix
drivers follow LiveView's client. This guide lists what a 0.8 suite must change, as one
step from 0.8; the [changelog](../CHANGELOG.md) has the details.

From an earlier release, also read the changelog up to 0.8. The 0.8 change most likely
to bite: LiveView sessions see the root layout and portal content, so a locator that
matched once can now match twice.

## Setup

- Install the pinned driver and a browser with `mix playwright_ex.install -- chromium`.
  Drop the npm `playwright` package and the `assets_dir` config; Node.js is no longer
  needed. `executable:` now takes a Playwright 1.65 CLI such as
  `node_modules/.bin/playwright`, not `cli.js`; usually drop it and let PlaywrightEx
  install the driver.
- Run the install in CI too, with `-- chromium --with-deps` on Linux runners; the driver
  would install itself in the first browser test, but browsers do not. For a system
  browser, as on Nix or in Docker, pass `--no-browsers` and set
  `launch_options: [executable_path: ...]` or `channel:`; see
  [Playwright setup](installation.md#playwright-setup).
- Prefer `only: [:dev, :test]` to `only: :test`, so PlaywrightEx's Mix tasks and
  `mix usage_rules.sync` work in `:dev`, and widen the `lazy_html` line `phx.new`
  generates to match. List PlaywrightEx too for its usage rules; see
  [Elixir dependency](installation.md#elixir-dependency).

  ```diff
  -    {:lazy_html, ">= 0.1.0", only: :test},
  -    {:fluffy, "~> 0.8.0", only: :test}
  +    {:lazy_html, ">= 0.1.0", only: [:dev, :test]},
  +    {:fluffy, "~> 0.9.0-rc.2", only: [:dev, :test]}
  ```
- Playwright 1.65's own breaking changes apply: actions wait for an element to be not
  inert, cookie matching follows RFC 6265, and text the browser does not render is no
  longer part of accessible names.
- Browser console messages are no longer logged, as in Playwright, and `js_logger:`,
  custom loggers and `Fluffy.Playwright.ConsoleLogger` are gone. To log them, register
  a listener: `on(session, Event.console(), &Logger.info(&1.text))`.
- Playwright sessions use Playwright's `en-US` locale instead of `en`; set
  `browser_context: [locale: "en"]` to keep it.
- Browser launch gets Playwright's 3-minute default instead of `timeout:`. A
  `launch_options: [timeout: ...]` that raised the limit on 0.8 now shortens it and can
  fail a loaded machine with `browserType.launch: Timeout ... exceeded`, so drop it.
- `browser_context:`, `launch_options:` and the options of `storage_state` and cookies
  pass through to PlaywrightEx, which rejects unknown ones. Page `screenshot/3`
  validates its options as `screenshot/4` does: `mask:` takes Fluffy locators,
  `timeout: 0` raises, and `path:` is only the argument.

## Timeouts

Timeouts follow Elixir: `0` checks once and `:infinity` means no limit; see
[Timeouts](installation.md#timeouts).

- Playwright actions, waits, `reload`, `go_back` and `go_forward` raise `ArgumentError`
  for `timeout: 0` instead of timing out after 1ms; pass a positive timeout. Assertions
  and Phoenix actions still check once. `config :fluffy, timeout:` must be positive.
- For no limit, pass `timeout: :infinity`, never Playwright's `0`.
- Playwright actions and expectations default to the session's `timeout:` from
  `Fluffy.start_session/2`, as on Phoenix, not only to the configured one.
- Calls that have no timeout in Playwright take no `timeout:`: `Fluffy.Playwright.evaluate`,
  `cookies`, `clear_cookies` and `storage_state`. Download `read` and `save_as` no longer
  end at the session's `timeout:`; an unfinished download waits until the test times out.

## Renamed and removed APIs

- `Fluffy.unwrap/2` passes a `%PlaywrightEx.Page{}` on Playwright instead of a
  `Fluffy.Playwright.Handle`, which is removed. The new `Fluffy.unwrap_and_return/2`
  returns the callback's result.
- `Fluffy.Playwright.evaluate(session, expression, arg)` replaces the `is_function:`
  and `arg:` options. JavaScript `null` returns `:null`.
- `Fluffy.Playwright.cookies(session, urls)` takes the URL list. Cookie maps use
  Playwright's camelCase keys (`httpOnly:`, `sameSite:`, `partitionKey:`), and
  `storage_state/2` returns atom keys: `state["cookies"]` becomes `state.cookies`.
- `Fluffy.HTTPEvent` is replaced by `Fluffy.Request` and `Fluffy.Response`, whose
  `request` field is the request.
- `Fluffy.Download`'s `read!` and `save_as!` are `read` and `save_as`. Only the
  documented fields of `Fluffy.Download` and `Fluffy.Dialog` remain public.
- `page_status`, `page_to_have_status` and `Fluffy.Page.status` are removed, as in
  Playwright; on Playwright, assert on `Fluffy.Event.response/1` instead.
- Configure the browser with `config :playwright_ex, :test, browser_name: ..., launch_options:
  ...` (`driver: [executable: ...]` for a CLI). `config :fluffy, :playwright` drops
  `enabled`, `engine`, `executable`, `launch_options` and `pool_size`; on Firefox, replace
  `pool_size` with a `setup_all` returning `PlaywrightEx.Test.browser(context, isolate: true)`
  in each browser module.
- `Fluffy.Playwright.trace/2`, `artifact_dir` and `trace_dir` are removed. Traces,
  screenshots and videos come from `PlaywrightEx.Test`: set
  `config :playwright_ex, :test, trace: :retain_on_failure, screenshot: :only_on_failure`
  and replace `setup context do Fluffy.Test.setup(context) end` with `use Fluffy.Test`
  (its options go to `use`) in modules or case templates. Files go to
  `test-results/<test>/`; a failed operation no longer writes HTML or the error text.
- `Fluffy.step/3` is `Fluffy.Playwright.step/4`, `PlaywrightEx.Test.step/3` in a pipeline.
  It raises `Fluffy.CapabilityError` on Phoenix, where it used to just run the callback.
- `filter/2` takes no `exact:`, as in Playwright. Match a whole text with a regex, such as
  `filter(has_text: ~r/^Pro$/)`, which works on every driver.
- The `Fluffy.Expect.checked_option` type is `to_be_checked_option`.
  `Fluffy.Locator.describe`, `new` and `append` are internal; `inspect/1` renders a locator.
- On Playwright, a failed `visit`, `reload`, `go_back` or `go_forward` raises
  `Fluffy.OperationError` instead of a `RuntimeError`. Its `cause`, like that of a
  failed action, is PlaywrightEx's exception.
- On Phoenix, `go_back` and `go_forward` raise `Fluffy.CapabilityError` with
  `capability: :browser_history` instead of `:pages`.

## Workarounds that can go

Most `unwrap` callbacks that called PlaywrightEx with the handle's `frame_id`,
`context_id` or `page_id` have a Fluffy function now. Replace them rather than port them:

- `add_init_script`: `Fluffy.Playwright.add_init_script/3`.
- `Frame.wait_for_function` with `is_function:` and `arg:`:
  `Fluffy.Playwright.wait_for_function(session, expression, arg)`.
- An `evaluate` of `document.querySelector(...)`, say to read a `dataset`:
  `Fluffy.Playwright.evaluate(session, locator, "el => el.dataset.state")`.
- `Frame.expect(expression: "to.be.in.viewport")`: `Fluffy.Assert.in_viewport/2` or
  `Fluffy.Expect.to_be_in_viewport/2`.
- `Page.route` with `PlaywrightEx.Route.fulfill`: `Fluffy.Playwright.route/4` with
  `Fluffy.Route.fulfill/2`.
- `BrowserContext.clock_install` and `clock_fast_forward`:
  `Fluffy.Playwright.Clock.install/2` and `fast_forward/3`.
- `Frame.press`: `Fluffy.press/4`, which takes any Playwright key.
- A click at a position, mouse moves or a bounding box: `click(session, locator,
  position: %{x: 5, y: 5})`, `Fluffy.Playwright.Mouse` and
  `Fluffy.Playwright.bounding_box/3`.
- `Frame.is_checked`, then a click on the label of a hidden input:
  `Fluffy.set_checked(session, by_css("label[for=terms]"), true)`. As in Playwright, the
  label stands for its input.

The other callbacks get a `%PlaywrightEx.Page{}`; see PlaywrightEx's
[migration guide](https://hexdocs.pm/playwright_ex/migration.html).

On Phoenix, `by_role` knows the landmark roles, so a `by_css("nav")` stand-in becomes
`by_role(:navigation)`, and a named `<section>` is `by_role(:region, name: "...")`.

## Phoenix behavior

The Phoenix drivers now act like a browser running LiveView's client, so some tests
that passed on 0.8 act differently:

- `click` sends the closest `phx-click`, the target's or an ancestor's, then takes the
  default action of the closest button or link: it submits the form or follows the link.
  On 0.8 it sent only the target's own `phx-click`, like `render_click`, and a click on
  text inside a button or link did nothing. A click inside a LiveView link patches or
  navigates, even past a closer `phx-click`, and `href="#"` has no default action.
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
