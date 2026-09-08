# Changelog

## 0.2.0 — 2026-09-08

### Changed

- **Breaking:** rename all `Fluffy.Expect` assertion constructors to fluent names. State assertions now use `to_be_*` (`visible` → `to_be_visible`, `checked` → `to_be_checked`, and likewise for disabled, editable, enabled, and focused). Property assertions use `to_have_*` (`count` → `to_have_count`, `value` → `to_have_value`, `values` → `to_have_values`). Captured-result assertions also gain `to_have_`, for example `download_url` → `to_have_download_url` and `response_status` → `to_have_response_status`.
- Keep `Page.to_have_*`, assertion options, negation, retry behavior, and matching semantics unchanged. Update existing calls to the new names; the old names are no longer exported.

## 0.1.1 — 2026-09-08

### Fixed

- Preserve entered Phoenix form values when nested LiveView session tokens change and when `phx-trigger-action` submits the form.

## 0.1.0 — 2026-09-08

### Added

- Initial release
