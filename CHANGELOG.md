# Changelog

## Unreleased

### Changed

- On Firefox, an action that closes its own page, such as a popup's `window.close()`, raises `Fluffy.OperationError` again, as it does in Playwright, which tracks it as a Firefox bug. Other browsers are unchanged.

### Fixed

- On Playwright, a session `timeout:` under a second no longer limits Fluffy's own reads of the page around an operation; they get at least a second, so a busy browser is far less likely to fail such a session with a `RuntimeError` naming a blocked script. A page whose main thread is blocked now reports after that second.
- A page that closes while Fluffy adopts its document now fails the operation with `Fluffy.OperationError`, or an `ExUnit.AssertionError` from an expectation, instead of a `RuntimeError` about the LiveView connection. `unwrap`, clock calls, `visit`, `reload` and history navigation raise PlaywrightEx's closed-page error. An operation that succeeded is not failed by its page closing during the bookkeeping after it.

## 0.9.0-rc.1 — 2026-11-09

### Added

- `by_role` on Phoenix knows Playwright's implicit roles for everything markup can decide, landmarks included: `article`, `banner`, `complementary`, `contentinfo`, `form`, `main`, `navigation`, `region` and `search`, plus the likes of `paragraph`, `group`, `dialog`, `searchbox` and `status`. The usage guide has the full list.
- `Fluffy.Expect.to_be_in_viewport/2` and `Fluffy.Assert.in_viewport/2`, with `ratio:` from 0 to 1, for Playwright; Phoenix raises `Fluffy.CapabilityError`.
- `Fluffy.Playwright.add_init_script/3` runs a script in every later document of the session's browser context.
- `Fluffy.Playwright.wait_for_function/4` waits on the active page and returns the session, within the session's `timeout:` unless `timeout:` is given. A non-empty keyword list in the argument position is options, so `wait_for_function(session, expression, timeout: 100)` works; `[]` stays a JavaScript array.
- `Fluffy.Playwright.evaluate/4` accepts `timeout:`, overriding the session's, as `evaluate(session, expression, timeout: 100)` or `evaluate(session, expression, arg, timeout: 100)`.
- `Fluffy.Expect.to_have_css/4`, `to_have_js_property/4`, `to_have_role/3`, `to_have_accessible_name/3`, `to_have_accessible_description/3` and `to_have_accessible_error_message/3` for Playwright; Phoenix raises `Fluffy.CapabilityError`.
- `Fluffy.Expect.to_have_screenshot/2` and `page_to_have_screenshot/1` compare against the baseline at a required `path:`; Fluffy does not derive one from the test name. `to_match_aria_snapshot/3` and `page_to_match_aria_snapshot/2` compare an inline snapshot. Playwright only.
- `to_match_aria_snapshot/2` and `page_to_match_aria_snapshot/1` also take `path:` in place of the expected snapshot, a file resolved against the current working directory and written when missing unless `update_snapshots:` is `:none`. Needs PlaywrightEx 0.17.0-rc.4.
- `Fluffy.Playwright` gains `set_extra_http_headers/2`, which keeps the session's starting headers and Ecto sandbox header, `add_script_tag/2`, `add_style_tag/2`, `wait_for_load_state/3` and `unroute_all/2`, all returning the session, and `bounding_box/3`, `aria_snapshot/3` and `viewport_size/1`, returning the value. Phoenix raises `Fluffy.CapabilityError`.
- `Fluffy.wait_for/3` also takes a locator on Playwright, with `state:`: it blocks and returns the session, while an event still returns a pending handle. Phoenix raises `Fluffy.CapabilityError` for a locator.
- `Fluffy.Playwright.evaluate` and `wait_for_function` take a locator, and `evaluate_all/5` runs on all its elements, with the same options-or-argument matching.
- `Fluffy.Playwright` gains `drop/4`, `pdf/3`, `bring_to_front/2` and `set_storage_state/2`, returning the session, and `all/2`, `content/2`, `title/2`, `local_storage/2` and `session_storage/2`, returning the value.
- `Fluffy.Locator.within/2` scopes a locator to each match of another, with `nth/2` and `first/1` resolved per parent, on every driver.
- `Fluffy.Route.fetch/2` performs a routed request and returns the response for `Fluffy.Route.fulfill/2`.
- The facade's `assert_has` and `refute_has` accept a `%Fluffy.Locator{}` with the same options as a selector, inside the current `within/3` scope.
- `Fluffy.unwrap_and_return/2`, `Fluffy.Playwright.unwrap_and_return/3` and `Fluffy.PhoenixTest.unwrap_and_return/2` run a native callback and return its result. They reconcile like `unwrap`; a Static callback may return anything and leaves the page alone.

### Changed

- **Breaking:** `Fluffy.unwrap/2` takes only a session and returns it. Use `Fluffy.unwrap_and_return/2` for native values such as `Fluffy.Response`.
- Stricter name matching can stop Phoenix locators that only matched by content: `by_role(name:)` now takes a name from content only for the roles Playwright does. `<div role="navigation">Menu</div>` no longer matches `by_role(:navigation, name: "Menu")`, nor do other landmarks, `list`, `listitem` or `dialog`; a button or link no longer picks up text from a landmark inside it. Name those elements with `aria-labelledby`, `aria-label`, `title` or a native `legend`, `caption` or `figcaption`.
- `by_role` on Phoenix follows Playwright's other role and name rules too: it uses the first valid `role` token in any case and keeps the implicit role for an invalid one; `none` and `presentation` give way on focusable elements or with global ARIA attributes, and pass to list items and table parts; a blank `aria-label` or dangling `aria-labelledby` falls through to the next name source; and the implicit roles of `th`, `img` and `input` changed to match.
- A scoped `by_role` on Phoenix no longer matches its scope element, and sees hidden ancestors, labels and `aria-labelledby` targets outside its scope. A `datalist` counts as hidden. Phoenix locators do not model `details`, `dialog`, `popover` and dropdown `select` open state: content inside them stays visible on Phoenix, as on 0.9.0-rc.0, while Playwright needs them opened first.
- Controls inside `<noscript>` are no longer submitted on Phoenix, as in a browser with scripting on, and a form inside `<noscript>` no longer owns its controls.
- A `select` in a disabled `fieldset` keeps its default option on Phoenix, as in a browser, so `to_have_value` reports it. The control is still left out of form submissions.
- Phoenix visibility checks (`to_be_visible`, `to_be_hidden`, `filter(visible:)` and the facade's `assert_has` and `refute_has`) now share one rendered rule with `by_role`. `aria-hidden` no longer counts, as in Playwright: a `to_be_visible` on an `aria-hidden` element passes and a `refute` on it fails, while `by_role` still excludes it. Elements a browser never displays, such as `<title>`, `<script>`, `<style>`, `<template>` or `<datalist>`, or fallback content inside `<video>` and the like, now count as invisible.
- The PhoenixTest-style `click_button(session, text)` no longer matches `<input type="file">`, so a file input labelled like a button is no longer ambiguous. `by_role(:button)` still matches file inputs, as in Playwright.

### Fixed

- Static and LiveView chained locators, `filter(has:)` and `within/3` search descendants only, as on Playwright, so a scoped locator no longer matches its own parent. `by_text` under a parent still matches the parent, as on Playwright. A Phoenix test that relied on matching the parent must drop the scope.
- The facade's `submit/2` resolves a `%Fluffy.Locator{}` inside the current `within/3` scope instead of the whole page.
- Playwright `check` and `uncheck` no longer pass on a box that stayed unchanged after an earlier activation of the same element, or when the target refuses the click and its handler calls `el.click()` on another checkbox.

## 0.9.0-rc.0 — 2026-11-09

Fluffy now runs on PlaywrightEx 0.17, a port of the official Playwright client with a pinned Playwright 1.65 driver.

### Upgrading from 0.8

- Install the driver and browsers with `MIX_ENV=test mix playwright_ex.install -- chromium`; drop the npm `playwright` package and the `assets_dir` config.
- Node.js is no longer required, for tests or for developing Fluffy: the driver brings its own.
- Playwright 1.65 is required. Its breaking changes apply: actions wait for an element to be not inert, and text the browser does not render is no longer part of accessible names.
- Replace `js_logger:` with `log_browser_console: true | false`; `Fluffy.Playwright.ConsoleLogger` is removed and custom `PlaywrightEx.JsLogger` modules are not supported.
- Browser `console.warn` messages log at `:warning` instead of `:info`.
- `executable:` now names a Playwright driver executable instead of the npm `cli.js`; drop it if it pointed at npm `playwright`.
- `unwrap/2` passes a `%PlaywrightEx.Page{}`; `Fluffy.Playwright.Handle` is removed.
- `Fluffy.HTTPEvent` is replaced by `Fluffy.Request` and `Fluffy.Response` (`response.request` is the request).
- `Fluffy.Playwright.evaluate(session, expression, arg \\ nil, options \\ [])` replaces the `is_function:` and `arg:` options, which now raise `NimbleOptions.ValidationError`, and raises after `timeout:` or the session's `timeout:`; JavaScript `null` returns `:null`.
- `Fluffy.Playwright.cookies(session, urls)` takes the URL list directly; the `urls:` and `timeout:` options now raise `ArgumentError`.
- Cookie maps of `add_cookies/2` and `cookies/2` use Playwright's camelCase atom keys: `%{name: "a", value: "b", url: url, http_only: true}` becomes `%{name: "a", value: "b", url: url, httpOnly: true}`, likewise `sameSite:` and `partitionKey:`; `add_cookies/2` raises on the old keys. `storage_state/2` returns atom keys instead of strings: `state["cookies"]` becomes `state.cookies`, likewise `:origins`, `:localStorage` and `:httpOnly`. Saved state files and string-keyed maps still load.
- `browser_context:`, `launch_options:`, and the options of `screenshot`, `storage_state`, cookies and `trace` pass through to PlaywrightEx, which validates them.
- `go_back`/`go_forward`, `hover`, `drag_to` and `press_sequentially` accept the options of their PlaywrightEx call except `no_wait_after:` and `signal:`, which would bypass navigation tracking.
- On Phoenix, `go_back`/`go_forward` raise `Fluffy.CapabilityError` with `capability: :browser_history` instead of `:pages`.
- On Playwright, a failed `visit`, `reload`, `go_back` or `go_forward` raises PlaywrightEx's exception, such as `PlaywrightEx.TimeoutError` or `PlaywrightEx.PlaywrightError`, instead of a `RuntimeError`.
- `trace(coverage:)` is removed.
- `Fluffy.Dialog.accept/2` and `dismiss/1` take no timeout; `Fluffy.Dialog` loses its `connection`, `id` and `timeout` fields, and `Fluffy.Download` its `timeout` field; `read!` and `save_as!` are renamed `read` and `save_as`, still raise after the session's `timeout:`, and now cancel the download so a pending save no longer writes the file later.
- `page_status`, `page_to_have_status` and `Fluffy.Page.status` are removed, as in Playwright; on Playwright, assert on `Event.response` instead.
- `OperationError.cause` and Playwright assertion messages carry native PlaywrightEx exceptions.
- `Fluffy.Expect.checked_option` is now `to_be_checked_option`.
- `Fluffy.Download` loses its `source` and `runtime` fields; its other fields besides `suggested_filename`, `url` and `page` are private. On Playwright, `unwrap_and_return(download, fun)` passes the `PlaywrightEx.Download`.
- `Fluffy.Locator.describe`, `new` and `append` are internal; `inspect/1` renders a locator.
- LiveView `set_input_files` on an upload input whose form has no id raises, saying to give the form an id, which LiveView's form recovery needs anyway.

### Added

- `click`, `fill`, `check`, `uncheck`, `select_option` and `press` accept the options of their PlaywrightEx call on Playwright (e.g. `modifiers: [:shift]`, `force: true`); Phoenix raises `Fluffy.CapabilityError` for them.
- `reload` accepts `wait_until:` on Playwright; Phoenix raises `Fluffy.CapabilityError` for it.
- `by_role` accepts Playwright's `checked:`, `disabled:`, `expanded:`, `include_hidden:`, `level:`, `pressed:`, `selected:` and `description:`, and `name:`, `has_text:` and `has_not_text:` accept a regex. These are Playwright only; Phoenix raises `Fluffy.CapabilityError` when it resolves such a locator.
- Expectations accept the options of their PlaywrightEx assertion on every driver: `visible:`, `enabled:` and `editable:` (`false` asserts the opposite state) and `ignore_case:` for `page_to_have_url`. Options and types are generated per constructor.
- A document navigated natively (inside or after `unwrap/2`) is adopted before the next action.
- Fluffy relaunches the browser after it disconnects.
- `Fluffy.Playwright.unwrap/3` runs a callback with the `PlaywrightEx.Locator` of a Fluffy locator, resolved through frame locators, and adopts the navigation it causes.
- `unwrap/2` accepts a `Fluffy.Request`, `Fluffy.Response`, `Fluffy.Dialog`, `Fluffy.Download`, `Fluffy.FileChooser` or `Fluffy.Frame` and returns the callback's result with its PlaywrightEx counterpart, such as a response body.
- `Fluffy.FileChooser.page/1`, and `Fluffy.Dialog.page/1` with a `page` field.
- `Fluffy.Download.page/1` with a `page` field; on Phoenix, the page that started the download.
- `Fluffy.Event.close()` resolves with the selected page's handle when it closes.
- Playwright clock control in `Fluffy.Playwright.Clock`: `install`, `pause_at`, `run_for`, `fast_forward`, `resume`, `set_fixed_time` and `set_system_time`. Fluffy's waits work with a paused clock.
- `Fluffy.Expect` gains `to_have_text`, `to_contain_text`, `to_have_attribute`, `to_have_class`, `to_contain_class`, `to_have_id`, `to_be_attached`, `to_be_hidden` and `to_be_empty` on every driver, following Playwright's whitespace normalization, regular expressions, per-element lists and strictness. `use_inner_text:` is Playwright only; Phoenix raises `Fluffy.CapabilityError` for it.
- `Fluffy.clear/3` and `Fluffy.set_checked/4` work on every driver.
- `Fluffy.Playwright` gains `dblclick`, `tap`, `dispatch_event`, `select_text`, `scroll_into_view_if_needed`, element `screenshot`, `set_viewport_size` and `emulate_media`; `Fluffy.Playwright.Keyboard` and `Fluffy.Playwright.Mouse` send page-wide input. As in Playwright, page-wide input and `dispatch_event` do not wait for a navigation they start; `expect` on the new page before the next action. They accept their PlaywrightEx options except `no_wait_after:` and `signal:`, and raise `Fluffy.CapabilityError` on Phoenix.
- `Fluffy.Response` reads bodies and headers: `body`, `text`, `json`, `ok?`, `all_headers`, `header_value` and `header_values`, without `unwrap/2`. `Fluffy.Request` adds `all_headers`, `header_value`, `post_data_json`, `failure`, `redirected_from` and `redirected_to`. Reads raise after the session's `timeout:`.
- `Fluffy.Download.path`, which raises `Fluffy.CapabilityError` on Phoenix.
- `Fluffy.Playwright` changes the browser context at runtime with `grant_permissions`, `clear_permissions`, `set_geolocation`, `set_offline` and `set_http_credentials`, returning the session and raising after its `timeout:`; Phoenix raises `Fluffy.CapabilityError` for them.
- More Playwright events on `Fluffy.Event`: `console`, `page_error`, `worker` and `web_socket` (new values `Fluffy.ConsoleMessage`, `Fluffy.PageError`, `Fluffy.Worker` and `Fluffy.WebSocket`), `request_failed` and `request_finished` (a `Fluffy.Request`, with `scope:`), `load`, `dom_content_loaded` and `crash` (a `Fluffy.Page`), and `frame_attached` and `frame_detached` (a `Fluffy.Frame`). Phoenix raises `Fluffy.CapabilityError` for them.
- `Fluffy.Playwright.route/4` and `unroute/3` intercept the requests of a session's browser context, with a new `Fluffy.Route` to `fulfill`, `continue`, `abort` or `fallback` them. A handler runs in its own process, allowed by the Ecto sandbox through `$callers`; a raising handler aborts the request and fails the test.
- `config :fluffy, :playwright, pool_size: n` runs a pool of browsers (default `1`). Sessions go to the least-loaded browser, ties to the lowest slot; each browser launches on first need, and a lost browser is launched again for the next session that needs it.

### Fixed

- `check` and `uncheck` on Playwright succeed when page code reverts the click in a frame that loaded after the action started.
- A LiveView `press` sends its keyup to the binding its target had when the press started, as a browser does: a keydown that removes, moves, or rebinds its target no longer drops the keyup or sends it to another element, even with `first()`, `last()`, or an input without an id. A keydown that removes the LiveComponent handling the key loses the keyup with `phx-target={@myself}`, and sends it to the view with a CSS selector, since LiveViewTest has destroyed the component by then.
- LiveView cancels an upload whose form a render shifted, still submits a form whose last upload moved it, keeps an upload whose input a render removed for that submit to consume, and uploads through a `live_file_input` linked to its form with `form=`.
- No unused-function warning when Fluffy is compiled without Ecto.
- A Playwright session starts when `config :fluffy, :playwright` leaves out `timeout:`, using its 15 seconds default instead of raising `KeyError`.
- Playwright actions and expectations default to the session's `timeout:`, like LiveView.
- Playwright `reload(timeout:)` bounds the reload only; the LiveView connection wait after it uses the session's `timeout:`, as after other actions.
- An action that closes its own page, such as a popup's `window.close()`, succeeds instead of raising `PlaywrightEx.TargetClosedError`.
- An event of a page that closed before Fluffy saw it, such as a popup that closes at once, resolves with that page's closed handle instead of raising; a request's page is nil.
- A browser that fails to launch raises in the session that needed it, instead of restarting every running session.
- Playwright `check` and `uncheck` succeed once the click sets the requested state, as on Phoenix, even if page code such as a LiveView patch changes it before Playwright reads it back (common in Firefox and WebKit).
- Playwright `submit` waits for the server to answer the navigation it starts, following its redirects, so it no longer returns before WebKit has sent the form. A submission the browser handles within the document (a GET to a fragment of the current URL, a Navigation API `intercept()`) ends the wait, as does a `beforeunload` prompt.
- On Phoenix, a link, form submission or redirect answered with `204 No Content` or `205 Reset Content` keeps the current page, URL and form state instead of showing an empty document; a LiveView page stays, disconnected, as in a browser. `visit` to such a response raises, like Playwright's.
- On Chromium, a link or form submission answered with `204 No Content` no longer leaves later actions waiting on the aborted navigation.
- On Playwright, a LiveView navigation whose new view patches as it mounts (`phx-mounted={JS.patch(...)}`) is followed as a navigation instead of a patch, so Fluffy awaits the new view and the PhoenixTest facade drops the old page's active form.
- A Playwright action whose navigation lands on pages that navigate again on load (a client-side redirect chain) follows them instead of raising "Execution context was destroyed".
- LiveView follows a redirect that lands while Fluffy reads the view after mount, an event or a retry, instead of crashing in `LazyHTML.from_fragment/1` or on a `GenServer.call` exit.
- LiveView follows a `push_navigate` or `redirect` from a view's connected mount, as a browser does, instead of raising "LiveView navigation failed". Mount redirects count toward the 20-redirect limit, so a loop fails instead of hanging. A connection LiveView rejects as stale or unauthorized, such as across live_sessions, still raises "LiveView navigation failed" with that cause.
- A LiveView action on a view that navigated away since Fluffy last read it follows the navigation and acts on the new page, as Playwright does, instead of failing with a LiveView error. A target missing there fails like any missing target, and an action whose timeout ran out before it reached the view fails as having navigated away, without acting on the new page. An action whose page navigates partway, such as between a press's keydown and keyup, ends on the new page without repeating there. A patch the view pushed meanwhile applies in place, so the action acts on the patched document instead of the one before. Pages that keep navigating before the action reaches them, such as views that navigate to each other as they connect, fail the action at the 20-redirect limit instead of retrying it until its timeout, and the redirects of a page it follows count toward the same limit. An expectation on such pages fails there too instead of retrying without end.
- A LiveView action goes on after one of its steps patches the URL, as in a browser: a patching keydown still sends keyup, a patching checkbox click its `phx-change`, and a patching upload progress or change handler lets the upload and submit finish. A form that patches after consuming its uploads can be submitted again.
- A LiveView upload survives a render that inserts content before its form, instead of failing at submit with "cannot consume uploaded files when entries are still in progress".
- LiveView `set_input_files` and upload submits follow a navigation from an upload progress callback right away instead of treating it as an entry error.
- LiveView `submit` and `set_input_files` wait for their target within the action's timeout, like `click`.
- On Phoenix, `to_be_visible`, `filter(visible:)` and `assert_has` treat a descendant of a `hidden` element and an `<input type="hidden">` as invisible, as Playwright does.

## 0.8.0 — 2026-11-04

### Added

- `Fluffy.Playwright.trace/2` accepts `coverage: true` to record Istanbul coverage from instrumented page code (`window.__coverage__`) into the trace archive.
- LiveView sessions see the full document: the root layout around the LiveView, `live_title` updates in `<title>`, and portal content in its target. Layout and portal elements can be located and acted on.

### Changed

- Playwright 1.64 or later is required.
- LiveView title assertions read `<title>`, including `live_title` prefix and suffix, matching Static and Playwright.
- LiveView `open_browser` writes the composed document instead of calling `Phoenix.LiveViewTest.open_browser/2`.

### Fixed

- LiveView no longer moves local checkbox, radio, select, or file state onto a different id-less control when a patch shifts it, and a radio group never ends a patch with more than one checked radio.
- LiveView marks only the activated radio as used, not the radios it unchecks, so a patch that shifts the group no longer suppresses `_unused_` params for other fields.
- LiveView marks every control of a `phx-submit` form as used, like the browser, so later change events no longer send `_unused_` params that hide `used_input?` errors after a failed submit.

## 0.7.0 — 2026-10-05

### Changed

- Restrict filling contenteditable elements to Playwright. Static and LiveView now raise `Fluffy.CapabilityError` instead of storing a synthetic form value.

- Move `focus` and `blur` to `Fluffy.Playwright`; focus assertions now require Playwright. Remove Phoenix focus tracking and focused-text preservation during LiveView patches. Other form-state reconciliation rules are unchanged.

- Remove native reset-button emulation from Static and LiveView. Reset buttons still dispatch supported LiveView events, but restoring form defaults requires Playwright.

- Move `current_page`, `pages`, `switch_page`, `close_page`, `new_page`, `go_back`, `go_forward`, `hover`, `drag_to`, and `press_sequentially` from `Fluffy` to `Fluffy.Playwright`. Update qualified calls or imports to the new module. All page-management helpers now reject Phoenix sessions.
- Simplify `press`: Static always raises `Fluffy.CapabilityError`; LiveView passes arbitrary keys unchanged through LiveViewTest keyboard handlers, without browser default actions or key filtering; Playwright retains native keyboard behavior. Remove simulated focus traversal, Space activation, and implicit Enter submission from Phoenix.

## 0.6.3 — 2026-10-02

### Added

- `Fluffy.Assert.assert_has/2,3` and `refute_has/2,3` as shortcuts for visibility assertions.

## 0.6.2 — 2026-10-02

### Changed

- Allow newer `playwright_ex` 0.x releases, keeping 0.13.0 as the minimum version.

### Fixed

- Prevent false Playwright connection timeouts when a parent LiveView update removes a connected nested view's `phx-connected` class. Readiness checks use the bound LiveView's connection and join state when available.

## 0.6.1 — 2026-10-02

### Added

- Locator `filter(visible: true | false)` uses structural visibility in Static/Live and rendered visibility in Playwright.

### Changed

- **PhoenixTest facade:** `assert_has` requires any visible match and `refute_has` requires no visible matches, instead of checking DOM presence, when no count or field predicate is supplied. Multiple matches remain allowed. Counts and field predicates add no visibility requirement, matching native assertions.
- **PhoenixTest facade:** CSS `click_link` prefers text matches and falls back to labels only when no text match exists. Ambiguous or non-actionable text matches remain errors.
- **Native API:** Static/Live visibility assertions now reject ambiguous locators, matching Playwright.
- Remove page names. `new_page/1` returns a page handle without changing the session's current page; use `switch_page/2` to select it. Switching, closing, and opener assertions accept page handles instead of names. Remove `new_page/2`, `page_names/1`, and `Fluffy.Page.name(page)`. See [Events and pages](docs/advanced-events.md) for migration examples.

## 0.6.0 — 2026-10-01

### Added

- `Fluffy.PhoenixTest` provides a slim PhoenixTest-style vocabulary (`visit`, `click_link`, `fill_in`, `select`, `check`, `within`, `assert_has`, `assert_path`, and friends) over Fluffy sessions from a single import. Unsupported options and combinations raise `ArgumentError`.
- `open_browser/2` opens an HTML snapshot from any driver for inspecting a test's current page.
- Independent `wait_for/3` and `await/1` event waits, pipeable `expect_event` and `assert_event` helpers, and persistent `on`, `once`, and `off` listeners. Predicates select events; ordinary ExUnit assertions check the returned values.
- Live browser frame handles from `Event.frame_navigated/1`, page/context request and response scopes, and dialog handles with explicit acceptance or dismissal.
- Download handles expose metadata when downloading starts. `Download.read!/2` and `Download.save_as!/2` wait for completion; reads retain the default 10 MB limit and saves use bounded memory.

### Changed

- **Breaking:** replace keyed event captures, callback-style `wait_for`, captured-result assertion constructors, and `Event.navigation` with independent waits and ordinary values. Use page URL/status assertions for cross-backend navigation outcomes. See [Events and pages](docs/advanced-events.md) for migration examples.
- Sessions and pages are live handles backed by shared session state. Actions remain visible through existing handles, while page selection stays local to each session handle. Closed pages reject subsequent operations, and session resources close with their owning test process.
- Form actions accept values implementing `String.Chars`. The PhoenixTest facade retains its wrapper, scoped operations, and active-form tracking for `submit()`.
- Require `playwright_ex ~> 0.13.0` for synchronous event cleanup and page frame-navigation events.

### Fixed

- Resolve Phoenix `:checked` selectors and selected-option assertions against current user input as well as server-rendered form state.
- Keep in-process DOM indexes local to the calling test process to avoid copying them through the session runtime on every operation.
- File chooser handles retain their source page, reconcile navigation there, and preserve the caller's page selection.
- Popup events resolve without waiting for loading; subsequent actions and assertions wait for document readiness and LiveView connection.

## 0.5.2 — 2026-09-28

### Fixed

- Allow managed LiveView uploads across the dependency versions accepted by `mix.exs`, removing the runtime restriction to LiveView 1.2.11.

## 0.5.1 — 2026-09-17

### Added

- `new_page/2` creates and activates a named browser page in the existing session.
- `go_back/2` and `go_forward/2` navigate browser history, and `close_session/1` releases session resources early.
- `hover/3`, `drag_to/4`, and `press_sequentially/4` provide native browser interactions with strict locators and navigation reconciliation.
- `Fluffy.Playwright` helpers add, query, and clear cookies, and export reusable storage state to a map or JSON file.

### Fixed

- Restore exported browser storage state from string-keyed maps and JSON files.
- Route page activation through the session's Playwright connection when bringing its tab to the front.

## 0.5.0 — 2026-09-16

### Added

- Lazy Playwright frame locators, nested frame scopes, `content_frame/1`, and `Fluffy.FrameLocator.owner/1`.
- `Fluffy.OperationError` for element-action failures across drivers, carrying backend, driver, operation, locator or file-chooser key, and the original cause.

### Changed

- Browser action failures, including `submit` and file selection, now preserve native Playwright errors and call logs instead of inferring `Fluffy.StrictnessError` or `Fluffy.ActionabilityError` from a later DOM snapshot. Callers rescuing structural errors from public actions should rescue `Fluffy.OperationError` instead. Static and LiveView preserve structural errors in `cause`, wrapping only after action retries finish. Assertions remain `ExUnit.AssertionError`; invalid arguments and unsupported capabilities stay distinct.
- Browser assertions continue to raise `ExUnit.AssertionError`, retaining Playwright's received values, timeout details, and call logs. Candidate markup is no longer reconstructed.
- Require `playwright_ex ~> 0.12.0` for locator evaluation and native assertion diagnostics.

### Fixed

- Enforce strict locator resolution for focus, blur, and key presses, including ambiguous iframe owners.

## 0.4.0 — 2026-09-15

### Added

- Filter download capture by `filename:` (string or regex) and `url:` (absolute string, regex, or URI predicate) on both backends.
- Accept `fn %URI{} -> boolean end` in page and captured-result URL assertions, including negation.

### Changed

- Centralize deadline calculations across event capture, browser navigation, and LiveView retries while preserving their timeout behavior.
- Retry failed CI tests once with the same seed, reporting the retry and retaining browser failure artifacts from both attempts. Formatting, compilation, and lint checks must pass before tests run.
- Require `playwright_ex` 0.11 or newer for `Frame.snapshot/2`, `Request.response/2`, and managed event waiters.
- Delegate browser URL waiting to `Frame.wait_for_url/2` and event capture to `EventWaiter`. Captures retain the first matching event, even when several arrive before the action returns; the capture timeout starts when arming.
- Save browser downloads through `PlaywrightEx.Download`. Temporary copies are removed after reading; source artifacts remain available until the browser context closes.
- Use waiter transforms for captured metadata and dialog decisions, removing Fluffy’s event listener, dialog handler process, subscription registry, and snapshot messages. The connection manages event subscriptions.
- Unexpected predicate and handler failures propagate instead of being converted into event errors.

### Fixed

- Read browser URLs and document identity from atomic frame snapshots. Same-URL reloads adopt their new response; requestless documents clear the previous HTTP status.

- Preserve zero-timeout URL assertions as a single current-state check instead of a one-millisecond wait.
- Keep captured navigation and HTTP metadata readable after the action closes its page.
- Retrieve navigation responses directly from their requests, avoiding the response-cache handoff race. Read committed document requests from `playwright_ex` for automatic navigation and popup initialization, removing Fluffy’s navigation recorder and its subscriptions.
- Give captured popups a separate session timeout for initialization, even when the action outlives the capture deadline.
- Use the session timeout to save a captured browser download, including when the callback returns after the event deadline.
- Ignore Phoenix navigation and download events arriving after the armed capture deadline, before applying download filters or byte limits.
- Load browser download metadata before decoding the first download event.
- Retain the first navigation on Phoenix's Static and LiveView drivers, including patches and fragment changes, when the callback continues navigating.
- Ignore history metadata updates that leave the URL unchanged when capturing navigation; same-URL document reloads still count.
- Associate navigation results with the committed request and popup responses with the captured page, preserving final redirect status. Capturing an earlier navigation no longer overwrites a later page's status.

## 0.3.1 — 2026-09-14

### Fixed

- Correct the session type declaration to reflect its shared implementation across backend modules. Consumer tracing, screenshot, and evaluation pipelines now pass Dialyzer without suppressions; session fields remain internal.
- Improve Playwright assertion reliability with short timeouts.

## 0.3.0 — 2026-09-09

### Changed

- **Breaking:** consolidate assertion execution, negation, and constructors in `Fluffy.Expect`. Import it for `expect` and `not_`. Page and captured-result constructors now use target prefixes, such as `page_to_have_url` and `response_to_have_status`; the old constructors on subject modules are removed.
- Add `use Fluffy.Assert` for pipeable `assert` and `refute`, with short constructors such as `visible`, `page_url`, and `response_status`. Ordinary ExUnit assertions remain available.

### Fixed

- Correct negated count expectations in the Static driver.

## 0.2.0 — 2026-09-08

### Changed

- **Breaking:** rename all `Fluffy.Expect` assertion constructors to fluent names. State assertions now use `to_be_*` (`visible` → `to_be_visible`, `checked` → `to_be_checked`, and likewise for disabled, editable, enabled, and focused). Property assertions use `to_have_*` (`count` → `to_have_count`, `value` → `to_have_value`, `values` → `to_have_values`). Captured-result assertions move to subject modules: `Download.to_have_url`, `Dialog.to_have_message`, `Navigation.to_have_url`, `Request.to_have_method`, and `Response.to_have_status`. Response request metadata is explicit in `Response.to_have_request_method` and `Response.to_have_request_post_data`.
- Separate internal navigation transitions from public captured-navigation assertions. Remove duplicated subjects from captured-result assertion failures.
- Captured URL assertions accept exact strings, regexes, and structured path, query, and fragment matchers. Structured matching shares page URL semantics, including exact and subset query matching; relative strings are not resolved.
- Keep `Page.to_have_*`, assertion options, negation, and retry behavior unchanged. Update existing calls to the new names; the old names are no longer exported.

## 0.1.1 — 2026-09-08

### Fixed

- Preserve entered Phoenix form values when nested LiveView session tokens change and when `phx-trigger-action` submits the form.

## 0.1.0 — 2026-09-08

### Added

- Initial release
