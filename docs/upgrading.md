# Upgrading to 0.9

Fluffy 0.9 runs on PlaywrightEx 0.17, a port of the official Playwright client with
a pinned Playwright 1.65 driver. It follows Playwright more closely, and its Phoenix
drivers follow LiveView's client. This guide lists what a 0.8 suite must change, as one
step from 0.8; the [changelog](../CHANGELOG.md) has the details.

## Setup

- Install the pinned driver and a browser with
  `MIX_ENV=test mix playwright_ex.install -- chromium`. Drop the npm `playwright` package
  and the `assets_dir` config; Node.js is no longer needed. `executable:` now names a
  Playwright driver, so drop it if it pointed at npm's `cli.js`.
- Playwright 1.65's own breaking changes apply: actions wait for an element to be not
  inert, and text the browser does not render is no longer part of accessible names.
- Browser console messages are no longer logged, as in Playwright. Replace `js_logger:`
  with `log_browser_console: true` to log them; custom loggers and
  `Fluffy.Playwright.ConsoleLogger` are gone, and `console.warn` logs at `:warning`.
- Playwright sessions use Playwright's defaults: the `en-US` locale instead of `en`,
  and a 3-minute browser launch timeout instead of `timeout:`. Set `browser_context:
  [locale: "en"]` or `launch_options: [timeout: ...]` to keep the old ones.
- `browser_context:`, `launch_options:` and the options of `screenshot`, `storage_state`,
  cookies and `trace` pass through to PlaywrightEx, which rejects unknown ones.

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
- `trace(coverage:)` is removed.
- The `Fluffy.Expect.checked_option` type is `to_be_checked_option`.
  `Fluffy.Locator.describe`, `new` and `append` are internal; `inspect/1` renders a locator.
- On Playwright, a failed `visit`, `reload`, `go_back` or `go_forward` raises
  `Fluffy.OperationError` instead of a `RuntimeError`. Its `cause`, like that of a
  failed action, is PlaywrightEx's exception.
- On Phoenix, `go_back` and `go_forward` raise `Fluffy.CapabilityError` with
  `capability: :browser_history` instead of `:pages`.

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
- Visibility ignores `aria-hidden`, as in Playwright, while `<title>`, `<script>`,
  `<template>` and similar content counts as hidden.
- `select_option` with `[]` deselects every option, and a list mixing values with
  option maps raises. `to_have_values` requires a multiple select.
- The facade's `click_button` no longer matches `<input type="file">`.
- LiveView `set_input_files` raises unless the upload's form has an id.

Rarer differences follow the browser too: some implicit roles and accessible names
changed, text in `<template>`, `<script>` and `<style>` no longer matches text
locators, controls inside `<noscript>` are not submitted, `press` raises in layout
content without key bindings, and a render resets local field state only in the
views it changed. See the [changelog](../CHANGELOG.md) for the full list.
