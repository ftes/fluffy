# Changelog

## Unreleased

### Added

- Filter download capture by `filename:` (string or regex) and `url:` (absolute string, regex, or URI predicate) on both backends.
- Accept `fn %URI{} -> boolean end` in page and captured-result URL assertions, including negation.

### Changed

- Retry failed CI tests once with the same seed, reporting the retry and retaining browser failure artifacts from both attempts. Formatting, compilation, and lint checks must pass before tests run.
- Require `playwright_ex ~> 0.10`.
- Delegate browser URL waiting to `Frame.wait_for_url/2` and event capture to `EventWaiter`. Captures retain the first matching event, even when several arrive before the action returns; the capture timeout starts when arming.
- Save browser downloads through `PlaywrightEx.Download`. Temporary copies are removed after reading; source artifacts remain available until the browser context closes.
- Unexpected predicate and handler failures propagate instead of being converted into event errors.

### Fixed

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
