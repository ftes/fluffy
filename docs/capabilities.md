# Capability matrix

The table compares Fluffy's Phoenix and Playwright backends within the
boundaries described below.

- **equivalent** — matching behavior verified against Playwright;
- **structural subset** — supports HTML-represented state, with browser-only
  behavior excluded;
- **-** — unavailable or not applicable.

<!-- capability-matrix:start -->
| Feature | Phoenix | Playwright |
| --- | --- | --- |
| Documented CSS locator subset | equivalent | equivalent |
| Text, label, and attribute locators | equivalent | equivalent |
| Structural role and accessible-name subset | structural subset | equivalent |
| DOM assertions and strictness | equivalent | equivalent |
| Page title assertions | equivalent | equivalent |
| Indeterminate checkbox/radio DOM property | - | equivalent |
| Structural element actions | structural subset | equivalent |
| Visits, reloads, links, redirects, cookies, and HTTP forms | equivalent | equivalent |
| Phoenix.HTML data-method/data-to actions | structural subset | equivalent |
| LiveView events, patches, navigation, and structural action retry | equivalent | equivalent |
| LiveView form-change delivery and timing | structural subset | equivalent |
| Declarative LiveView keyboard events | structural subset | equivalent |
| Supported mutable form state and ordered submission | equivalent | equivalent |
| Structural Enter implicit form submission | structural subset | equivalent |
| Native constraint validation | - | equivalent |
| Specialized scalar input values | structural subset | equivalent |
| Computed style, layout, and browser accessibility tree | - | equivalent |
| Downloads | equivalent | equivalent |
| Named pages and new tabs | - | equivalent |
| Dialogs and browser request/response events | - | equivalent |
| Active-page JavaScript evaluation | - | equivalent |
| JavaScript-owned DOM and default actions | - | equivalent |
| Native invalid, submit, and formdata event ordering | - | equivalent |
| Hard-wrapped textarea, object, and custom-element entries | - | equivalent |
| Per-test sessions, cleanup, and Ecto sandbox propagation | equivalent | equivalent |
| Regex URL matching | equivalent | equivalent |
| Structured path, query, and fragment URL matching | equivalent | equivalent |
| Typed file selection and supported upload lifecycle | equivalent | equivalent |
| Script-opened file chooser events | - | equivalent |
<!-- capability-matrix:end -->

## Boundaries

### When to choose Playwright

Use Playwright for computed style, layout, browser accessibility, native
validation, arbitrary JavaScript, and browser network events. Phoenix operates
on parsed HTML and mutable form state. Even Phoenix checks structural
visibility; see [Visibility and DOM presence](usage.md#visibility-and-dom-presence)
for the distinction from browser rendering and DOM absence.

### LiveView timing and keyboard events

LiveView eagerly dispatches each applicable form-control `phx-change` and
ignores `phx-debounce`/`phx-throttle` scheduling. Use Playwright for delay,
blur-only delivery, coalescing, cancellation, and throttle suppression.

For Enter, Space, and Tab, LiveView dispatches the supported direct and window
`phx-keydown`/`phx-keyup` bindings, filters `phx-key`, preserves `phx-target`,
and orders events around the structural default action. Application-defined
LiveSocket metadata, modifiers and chords, repeats, browser timing, inline
listeners, and client-side `JS` commands remain Playwright-only.

### LiveView document and patch boundaries

LiveView locators and actions see the current `Phoenix.LiveViewTest.View`,
not the surrounding dead layout. Use `Phoenix.ConnTest` for initial
outer-layout HTML assertions or Playwright for full-document interactions.
LiveView `unwrap/2` receives only the View.

### Browser baseline

Fluffy verifies compatibility against pinned Chromium. Firefox and WebKit are
available through Playwright but are not covered by Fluffy's conformance suite.

### Phoenix.HTML actions and dialogs

For a Static or LiveView target with `data-confirm`, `click/2` ignores the
attribute and continues with the normal structural action. It does not create,
inspect, accept, or dismiss a browser dialog; use Playwright whenever the
prompt or its cancellation path is part of the assertion. Both in-process
drivers model the pinned Phoenix.HTML `data-method`/`data-to` hidden-form
action for plain elements, including links and buttons. Custom
`phoenix.link.click` listeners, cancellation, and competing LiveView actions
remain browser-only.

### Forms and files

Static and LiveView bypass native validation and retain specialized scalar
input values as supplied strings. Use Playwright for validation events and
blocking, browser sanitization/defaults, and custom or form-associated elements.

File selection supports bounded local paths and typed in-memory payloads,
ordered multiple selection, clearing, and ordinary multipart forms, including
empty-file entries. Managed LiveView uploads support validation, progress,
cancellation, replacement, auto-upload, and submission.

Native picker UI, external uploaders, directories, drag-and-drop, and arbitrary
`FileList` mutation are unsupported. `Event.file_chooser/2` requires Playwright
because application JavaScript opens the chooser.

### Native escape hatch

`Fluffy.unwrap/2` exposes driver-specific APIs: `Plug.Conn`,
`Phoenix.LiveViewTest.View`, or `Fluffy.Playwright.Handle`. Use the shared event
and page APIs for lifecycle operations. See
[Native escape hatch](usage.md#native-escape-hatch) for callback behavior.
