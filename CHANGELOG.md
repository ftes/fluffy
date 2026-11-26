# Changelog for v0.9

Fluffy 0.9 follows Playwright more closely on every driver. Upgrading from 0.8: the
[upgrade guide](docs/upgrading.md) lists what a suite must change, as one step.

## Built on the Playwright port

Fluffy runs on Playwright (Hex package `playwright_ex`), a port of the official JavaScript
client with a pinned Playwright 1.65 driver. `mix playwright.install` installs it; Node.js and
the npm package are no longer needed. Where Fluffy hands you Playwright's values, such as
events, routes, `unwrap` callbacks, regexes and URLs, they are the port's, as in Playwright.

## Playwright Test in ExUnit

`use Playwright.Test` registers each test, which every session needs. Browsers come from its pool,
and its options, timeouts, traces, screenshots, videos, steps and snapshot names follow Playwright
Test ([Configuration](docs/installation.md#configuration)). Its `assert` and `refute` are trace
steps, also with `use Fluffy.Assert`, which goes after `use Playwright.Test`. `:infinity` means no limit; `timeout: :once` checks once on assertions and Phoenix
actions, while Playwright actions and waits reject it.

## Phoenix drivers that act like a browser

Static and LiveView act like a browser running LiveView's client. A click takes the default
action of its button, link or label, events carry the form's current values, and roles,
accessible names, visibility and enabled state follow Playwright's rules. The app owns the Ecto
sandbox, as generated `DataCase` and `ConnCase` do.

## Backwards-incompatible changes

The entry below lists them under Breaking; the upgrade guide shows how to move a 0.8 suite.

## Unreleased

Changes since 0.8.0.

### Breaking

- Fluffy runs on Playwright (Hex package `playwright_ex`, `~> 1.65.0-rc.5`) with a pinned Playwright 1.65 driver, installed by `mix playwright.install`. The npm `playwright` package, `assets_dir` and Node.js are no longer needed; `executable:` names a Playwright CLI. Playwright 1.65's own breaking changes apply: actions wait for an element to be not inert, cookie matching follows RFC 6265, and text the browser does not render is not part of accessible names.
- Requires Phoenix 1.7.10 or later and Phoenix LiveView 1.1.32 or later, the floors CI now tests; LiveView 1.0 is no longer supported. Uploading several files through one input on the Phoenix drivers needs LiveView 1.2.10.
- PlaywrightEx is renamed `Playwright`: the app is `:playwright` and its modules `Playwright.*`, while the Hex package stays `playwright_ex`, and its versions follow Playwright's (major.minor is Playwright's). If you list it, write the dependency line from the installation guide (`hex: :playwright_ex` is required), rename `config :playwright_ex` to `config :playwright`, and port `PlaywrightEx.*` calls in `unwrap` callbacks with the breaking changes in Playwright's changelog. `alias Fluffy.Playwright` now shadows `Playwright.*`, so don't alias it where you call the dependency.
- `use Playwright.Test` after your `ConnCase` replaces `Fluffy.Test.setup`, which is removed. It registers the test, whose traces, screenshots, videos and `error-context.md` replace `Fluffy.Playwright.trace/2`, `artifact_dir` and `trace_dir`: record a module with `use Playwright.Test, trace: :on` and a describe block or test with `@tag Playwright.Test.use(trace: :on)`. A failed operation no longer writes HTML or the error text.
- Every session, Phoenix ones too, needs a registered test (`use Playwright.Test`) and raises outside one. `Fluffy.Case` of the 0.9 release candidates is removed: write `use Playwright.Test`, with the same options, in its place, also in a case template's body and `using`. A step then always records, and a screenshot's `path:` is never required.
- The application owns the Ecto sandbox, as generated `DataCase` and `ConnCase` do: Fluffy no longer starts, adopts or stops owners, and `sandbox:` and `repos:` are gone. It adds the metadata of `config :fluffy, ecto_repos:` to browser sessions.
- Browsers come from `Playwright.Test.BrowserPool`, configured by `config :playwright, :test` (`browser_name`, `launch_options`) and `config :playwright, :driver` (`executable:`), at most `workers` at once. `config :fluffy, :playwright` and `pool_size` are removed.
- Configuration follows Playwright Test: `config :fluffy` keeps only `endpoint`, `ecto_repos`, `file_input_max_bytes` and the new `phoenix_backend_timeout`; its `action_timeout:`, `expect_timeout:` (of the release candidates), `timeout:` and `base_url:` are removed ([Configuration](docs/installation.md#configuration)).
- Browser sessions take Playwright Test's timeouts from every level, tags included, and Phoenix sessions take `phoenix_backend_timeout`; `start_session(timeout:)` is removed. Calls with no timeout in Playwright, such as `evaluate`, `cookies` and download reads, take none ([Configuration](docs/installation.md#configuration)).
- A single check is `timeout: :once`, and `timeout: 0` raises in native calls, since it checks once in Elixir but means no limit in Playwright; the `Fluffy.PhoenixTest` facade keeps PhoenixTest's `0`. `:infinity` means no limit. Playwright actions and waits reject `:once`.
- Set the base URL with Playwright Test's `base_url` or a session's `base_url:`; by default it is the endpoint's ([Configuration](docs/installation.md#configuration)).
- The default base URL is the endpoint's `url` host, on its listener's scheme and port, instead of the listener's address: `http://localhost:4002`, not `http://127.0.0.1:4002`, with `phx.new`'s config. Phoenix's default `check_origin` now lets the browser's LiveView socket connect, and Phoenix sessions treat the app's own absolute URLs as same-origin when the `url` port is the listener's.
- Phoenix sessions send the test's `extra_http_headers`, and its `locale` (`en-US` by default) and `user_agent` as Accept-Language and User-Agent, as a browser does. `start_session`'s `headers:` is now `extra_http_headers:` (a map), which replaces the test's as in Playwright; it and `base_url` go there, not in `browser_context:` ([Configuration](docs/installation.md#configuration)).
- `config :fluffy` is validated at startup: an unknown key or the config of a missing module raises.
- Browser console messages are no longer logged, as in Playwright; `js_logger:` and `Fluffy.Playwright.ConsoleLogger` are removed. Register an `Event.console()` listener instead.
- Playwright sessions use Playwright's defaults: the `en-US` locale and a 3-minute browser launch timeout.
- `browser_context:`, `launch_options:` and the options of screenshots, `storage_state` and cookies pass through to Playwright, which validates them.
- Events deliver Playwright's values: a `Playwright.Request`, `Playwright.Response`, `Playwright.Dialog`, `Playwright.ConsoleMessage` and so on. `Fluffy.HTTPEvent` is removed. Page events, `Fluffy.Download` and `Fluffy.FileChooser` stay.
- `unwrap/2` passes a `%Playwright.Page{}` on Playwright and returns the session; `Fluffy.Playwright.Handle` is removed. Use `unwrap_and_return/2` for the callback's result.
- `Fluffy.Playwright.evaluate(session, expression, arg)` replaces `is_function:` and `arg:`; JavaScript `null` returns `:null`. `cookies(session, urls)` takes the URL list, cookie maps use Playwright's camelCase keys, and `storage_state/2` returns atom keys.
- `add_cookies`, `cookies` and `clear_cookies` move from `Fluffy.Playwright` to `Fluffy` and work on Phoenix sessions too, with Playwright's semantics and cookie maps.
- `Fluffy.Playwright.screenshot` and `pdf` return the image or PDF instead of the session; the path is the optional `path:`.
- `Fluffy.Download`'s `read!` and `save_as!` are `read` and `save_as`; only its documented fields remain public.
- `page_status`, `page_to_have_status` and `Fluffy.Page.status` are removed, as in Playwright; assert on `Event.response` instead.
- URLs are matched as Playwright does, by a string, a regex or a predicate, in `page_url`/`page_to_have_url` and `route`/`unroute`; the `path:`, `query:` and `fragment:` forms are removed.
- A regex is a JavaScript `RegExp` on every driver: PCRE-only syntax raises `ArgumentError`, and `$` no longer matches before a final newline.
- `by_test_id/2` takes no `attribute:`; set `test_id_attribute` in `config :playwright, :test`, which every driver uses (`config :fluffy, test_id_attribute:` of the release candidates is removed). `filter/2` takes no `exact:`; use a regex.
- On Playwright, a failed `visit`, `reload`, `go_back` or `go_forward` raises `Fluffy.OperationError` with Playwright's exception as `cause`, as actions do.
- On Phoenix, `go_back` and `go_forward` raise `Fluffy.CapabilityError` with `capability: :browser_history`.
- On Phoenix, page operations (actions, expectations, `reload`, `unwrap`, `open_browser`) raise `ArgumentError` before the first visit, where most raised `FunctionClauseError`. Cookie functions work there; `Fluffy.Playwright` calls and Playwright-only options raise `Fluffy.CapabilityError` as on any Phoenix page.
- `Fluffy.CapabilityError.capability` is always an id of `Fluffy.Capability.matrix/0`, with the call in a new `operation` field: ids such as `:hover`, `:press`, `:download_path` and `:browser_dialogs` are gone. `Fluffy.Capability` drops `matrix_version/0`, the `:experimental` status and the Playwright column, and `status/2` takes `:static` or `:live`.
- `Fluffy.CapabilityError` has a `backend` field, and `driver` is a page driver or `nil`. `browser:` and `browser_context:` on Phoenix and `conn:` on Playwright raise it instead of `ArgumentError`.
- Failed navigations raise `Fluffy.OperationError` with `locator: nil` on both backends, not `RuntimeError`: Phoenix aborted visits, redirect loops and LiveView connection failures, and Playwright LiveView readiness and document checks. A LiveView that exits during an operation raises `Fluffy.OperationError` with a `Fluffy.LiveViewError` cause.
- The `Fluffy.Expect.checked_option` type is `to_be_checked_option`; `Fluffy.Locator.describe`, `new` and `append` are internal.
- The Phoenix drivers act like a browser running LiveView's client:
  - `click` sends the closest `phx-click`, then takes the default action of the closest button, link or label: it submits the form, follows the link, or clicks the label's control, sending its `phx-click` and `phx-change`. A label takes its control's enabled state, and `check`/`uncheck` on a label click it.
  - `disabled` disables only native form controls, and text inside a disabled button is disabled.
  - Events carry what the browser sends: the form's current serialization, a control's current `value` and a `JS.push` `target:`. Clicking a checkbox or radio sends its form's `phx-change`.
  - `by_role` follows Playwright's role and name rules: landmarks, lists, list items and dialogs take no name from their content.
  - Chained locators, `filter(has:)` and `within/3` search descendants only.
  - Visibility ignores `aria-hidden`, and `<input type="hidden">`, `hidden` descendants, `<title>`, `<script>`, `<template>` and similar content count as hidden. Text matching skips `<script>`, `<style>` and `<template>`.
  - A dropdown `<select>`'s options count as hidden on Static and LiveView, as a closed dropdown's do in a browser, while role locators still find them. A facade `assert_has` on them, such as `assert_has("#house option", text: "Ravenclaw")`, and `to_be_visible` fail: check the selection with the facade's `selected:` or `by_role(:option, selected: true)` and count options natively. A failed `count:` or `at:` says how many matches are hidden ([Selects and options](docs/actions.md#selects-and-options)).
  - A `select` in a disabled `fieldset` keeps its default option, and the facade's `exact: true` no longer ignores soft hyphens and zero-width spaces.
  - Controls inside `<noscript>` are not submitted, `press` raises in layout content without key bindings, and a render resets local field state only in the views it changed.
  - `select_option` with `[]` deselects every option and rejects a list mixing values with option maps; `to_have_values` requires a multiple select; the facade's `click_button` no longer matches file inputs; LiveView `set_input_files` needs the upload's form to have an id.
- The PhoenixTest facade takes and returns a plain `Fluffy.Session`, so native calls go in the same pipeline; `Fluffy.PhoenixTest.Session` and its `.session` field are removed. Native calls don't see a `within/3` scope and don't change the form `submit/1` uses.
- The PhoenixTest facade's `assert_has` and `refute_has` count visible matches only for `count:` and `at:`, as PhoenixTest.Playwright did and as they already checked without them; a count of hidden elements becomes a native `count/2`. Field predicates without `at:` still check hidden inputs.

### Added

- `start_session(:playwright, browser: browser)` uses another browser, such as `BrowserPool.browser(headless: false)`.
- Actions, `reload` and expectations accept the options of their Playwright call, such as `modifiers:`, `force:`, `wait_until:`, `visible:` and `ignore_case:`; Phoenix raises `Fluffy.CapabilityError` for Playwright-only ones. `by_role` accepts Playwright's `checked:`, `disabled:`, `expanded:`, `include_hidden:`, `level:`, `pressed:`, `selected:` and `description:` on every driver; on Phoenix, `checked:` and `selected:` read the controls' current state.
- A regex in a locator's `name:`, `has_text:` and `has_not_text:`, on every driver.
- `Fluffy.Expect` gains `to_have_text`, `to_contain_text`, `to_have_attribute`, `to_have_class`, `to_contain_class`, `to_have_id`, `to_be_attached`, `to_be_hidden`, `to_be_empty`, `to_have_role`, `to_have_accessible_name` and `to_have_accessible_description` on every driver, and `to_have_css`, `to_have_js_property`, `to_have_accessible_error_message`, `to_be_in_viewport` (`Fluffy.Assert.in_viewport/2`), screenshot and aria snapshot assertions on Playwright. Snapshot names derive from the test, as in Playwright.
- `Fluffy.Assert` names every `Fluffy.Expect` matcher: `css`, `js_property`, `role`, `accessible_name`, `accessible_description`, `accessible_error_message`, `match_aria_snapshot`, `match_screenshot`, `page_match_aria_snapshot` and `page_match_screenshot` join the others.
- `Fluffy.Assert.page_path/1,2` checks the active page's path and optionally a subset or predicate over its decoded query parameters, on every driver.
- `by_role` on Phoenix knows Playwright's implicit roles, landmarks included.
- `Fluffy.Locator.Roles`, an opt-in import with `button("Save")` and `link("Owlery")`, shorthands for `by_role(:button, name: "Save")` and `by_role(:link, name: "Owlery")` that take the same options.
- `Fluffy.Locator.within/2`, `Fluffy.clear/3` and `Fluffy.set_checked/4` on every driver; the facade's `assert_has` and `refute_has` accept a locator.
- `Fluffy.wait_for/3` takes a locator and `state:`, as Playwright's `locator.waitFor()`, on every driver: LiveView retries against fresh renders and Static checks once.
- Locator reads, as Playwright's: `Fluffy.text_content/3`, `get_attribute/4`, `input_value/3`, `all_text_contents/2` and `all/2` on every driver, and `Fluffy.Playwright.inner_text/3` and `all_inner_texts/2`. Like upstream, they wait for the element but not for its value; assertions still retry.
- Page reads, as Playwright's: `Fluffy.content/2`, the page's HTML ([Page content](docs/capabilities.md#page-content)), and `title/2`, on every driver.
- `Fluffy.step/3` is `Playwright.Test.step/3`, on every driver, and `step/4` takes its options, such as `box:` and `subtitle:`.
- A Playwright session starts from the test's `Playwright.Test` context options of every level, such as `use Playwright.Test, locale: "en-GB"` or `@tag Playwright.Test.use(viewport: ...)`.
- `Fluffy.Playwright` gains `route/4`, `unroute/3` and `unroute_all/2` (handlers get a `Playwright.Route`), `unwrap/3` for a locator, `page/2`, `add_init_script`, `wait_for_function`, `wait_for_load_state`, `evaluate` on a locator and `evaluate_all`, `dblclick`, `tap`, `drop`, `dispatch_event`, `select_text`, `scroll_into_view_if_needed`, element `screenshot`, `bounding_box`, `aria_snapshot`, `set_viewport_size`, `viewport_size`, `emulate_media`, permissions, geolocation, offline mode, HTTP credentials, extra HTTP headers, script and style tags, `bring_to_front`, `set_storage_state`, `local_storage` and `session_storage`, plus `Fluffy.Playwright.Keyboard`, `Mouse` and `Clock`.
- More Playwright events: `console`, `page_error`, `worker`, `web_socket`, `request_failed`, `request_finished`, `load`, `dom_content_loaded`, `crash`, `frame_attached` and `frame_detached`, and `Event.close()`.
- `unwrap_and_return/2` (and `Fluffy.Playwright.unwrap_and_return/3`, facade `unwrap_and_return/2`) returns a native callback's result. A document navigated natively in a callback is adopted.
- `Fluffy.Download.path`, `Fluffy.Download.page/1` and `Fluffy.FileChooser.page/1`.
- On Phoenix, a link, form or redirect to another origin ends at a page with that URL, so a test can assert where the app sent it.
- `Fluffy.base_url/1`, the session's resolved base URL, as Playwright Test's `baseURL`.
- `Fluffy.add_session_cookie/3` starts a test logged in on both backends: it signs the endpoint's session cookie for the given session values, with the options of the endpoint's `session_options/0` ([Logging in](docs/usage.md#logging-in)).
- [Accessibility testing](docs/usage.md#accessibility-testing) links PlaywrightEx's axe-core recipe and its Fluffy calls.
- `Fluffy.Expect.poll/3` and `to_pass/2` (`Fluffy.Assert.poll/3` and `pass/2`) poll a value or retry a block in a pipeline, as Playwright's `expect.poll` and `toPass`, with the session, on every driver; `not_(to_pass(fun))` (`refute(pass(fun))`) as `not.toPass` ([Polling and retrying blocks](docs/assertions.md#polling-and-retrying-blocks)).

### Changed

- Playwright `submit` waits like a Playwright action, for its navigation to commit.
- Most of Fluffy's own error messages start with the call that raised them, such as `Fluffy.set_input_files/4: ...`.
- Playwright traces show only the test's own actions: Fluffy's document checks and LiveView waits are internal Playwright calls, with no trace entries or DOM snapshots.

### Fixed

- Before the test's sandbox owner stops, Playwright sessions started in the test process wait up to 5 seconds for the LiveViews they connected to exit, so a LiveView whose `terminate/2` uses the database no longer logs ownership errors after the test. A custom LiveView sandbox hook gets this by passing `Fluffy.Sandbox` to `Phoenix.Ecto.SQL.Sandbox.allow/2`, also on the static render: only LiveView processes are waited for ([Keeping your own LiveView hook](docs/installation.md#keeping-your-own-liveview-hook)).
- On Phoenix, `to_have_value` and `to_be_empty` read `"on"` for a checkbox or radio without a `value` attribute, as browsers do, instead of `""`.
- LiveView follows navigation as a browser does: a `push_navigate` or `redirect` from a connected mount, a redirect while Fluffy reads the view, an action on a view that navigated away, a patch partway through an action, and `phx-mounted={JS.patch(...)}` on a new view. Redirects count toward a 20-redirect limit, so a loop fails instead of hanging.
- On Phoenix, a `phx-trigger-action` form is submitted as LiveView's client does, from mount or a pushed render.
- On Phoenix, a `phx-trigger-action` form submits the values typed into text fields and textareas that its trigger render no longer echoes, such as phx.gen.auth's registration password, instead of `""`.
- On Phoenix, a `204 No Content` or `205 Reset Content` answer keeps the current page; on Chromium, a `204` no longer leaves later actions waiting.
- LiveView uploads survive renders that move or remove their form or input, follow navigations from progress callbacks, and work through a `live_file_input` linked with `form=`; `submit` and `set_input_files` wait for their target.
- A LiveView `press` sends its keyup to the binding its target had when the press started.
- On Playwright, an action that closes its own page succeeds, an event of a page that closed at once resolves, and a navigation into a client-side redirect chain is followed.
- Playwright `check` and `uncheck` no longer pass on a box that stayed unchanged.
- Static and LiveView compute editable, checked and disabled state and find labels as Playwright does.
- Phoenix requests no longer carry the sandbox header, and `on`/`once` handlers and `wait_for` predicates run with the test in `$callers`, so they can use its sandbox connection and mocks.
- The facade's `submit/2` resolves a locator inside the current `within/3` scope.
- The browsers and the driver close before `mix test` halts the VM, so the terminal is no longer left in the wrong mode ([#213](https://github.com/ftes/fluffy/issues/213)).
- No unused-function warning when Fluffy is compiled without Ecto.
- On LiveView, an error LiveViewTest's client raises, such as on a duplicate id, is the `Fluffy.LiveViewError`'s message, instead of the view's `{:shutdown, :closed}` exit.
- A Phoenix session sends its `conn:`'s `accept` and `authorization` headers with every request, as `Phoenix.ConnTest.recycle/2` keeps them, not only with the first, so an app behind basic auth no longer rejects later requests.

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
