# Changelog

## Unreleased

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
