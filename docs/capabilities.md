# Capability matrix

Version 1 describes Fluffy's initial public compatibility surface. The table
uses the two backends selected at session startup. The Phoenix backend chooses
the Static or LiveView driver for every page; the Playwright backend uses the
Playwright driver.

The matrix records which backend provides each feature and where its drivers
have explicit boundaries.

A status applies only to the feature as described here and in its conformance
tests; it is not a claim that an Elixir DOM is a complete browser
implementation.

- **equivalent** — the paired oracle corpus demonstrates the supported public
  contract;
- **structural subset** — Phoenix implements DOM-represented facts and names
  the excluded browser facts;
- **-** — this backend does not provide the behavior;
- **experimental** — no stable initial-release contract is advertised.

`-` covers both features that require a browser and features that do not apply
to that backend.

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

The Phoenix backend operates on parsed HTML plus Fluffy-owned mutable
properties. Its drivers deliberately ignore layout, generated content, and
computed visibility rather than attempting partial CSS analysis; use
Playwright when a test asserts those facts. Native-validation behavior,
arbitrary JavaScript, browser network streams, and JavaScript-created events
are Playwright territory too. The matrix uses `-` for those boundaries rather
than pretending that server-rendered HTML can bark like a browser.

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

On a LiveView page, the in-process locator and action surface is limited to the
DOM owned by the current `Phoenix.LiveViewTest.View`. The dead layout
surrounding `[data-phx-main]` is part of the browser document but not the
LiveViewTest event tree, so Fluffy does not merge it into the in-process
LiveView DOM. Initial outer-layout rendering assertions remain direct
`Phoenix.ConnTest` response coverage; interactions with that layout use
Playwright. This prevents a locator from resolving an element that the
selected in-process driver cannot act upon.
LiveView `unwrap/2` exposes only the View and therefore does not bypass this
boundary.

### Browser baseline

The stable compatibility baseline is pinned Chromium. Firefox and WebKit
support is inherited from Playwright rather than verified by a duplicate
Fluffy engine matrix. Known platform differences remain tagged in the
conformance corpus so applications selecting another engine have explicit
boundaries without weakening the shared Chromium contract.

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

An `equivalent` form claim applies to the supported form model, not general
native constraint validation. Static and LiveView bypass native validation and
submit structurally; only Playwright models invalid events and blocking. The
claim also excludes browser sanitization/defaults for specialized scalar input
states and custom/form-associated elements. Static does reproduce multipart
text entries and browser-shaped empty-file entries when no file has been
selected. The file-selection row covers bounded local paths and typed in-memory
payloads, ordered multiple selection, clearing, ordinary multipart forms, and
the paired managed-LiveView validation, progress, cancellation, replacement,
auto-upload, and submission lifecycle. Native picker UI, external uploaders,
directories, drag-and-drop, and arbitrary `FileList` mutation remain outside
that contract. `Event.file_chooser/2` is separately Playwright-only because it
depends on application JavaScript opening a browser chooser. Static and LiveView
retain specialized scalar input values as supplied strings; Playwright remains
the browser-semantics oracle.

### URL matching

`Page.to_have_url/1` runs one matcher against the canonical serialized page URL
for Static, LiveView, and Playwright. Exact strings include query serialization
and fragment; relative strings resolve against the session base URL. Elixir
regular expressions see the same complete string on every driver.

The structured form can select `:path`, `:query`, and `:fragment`. Omitted
components are ignored. Query matching decodes names and values with
URLSearchParams semantics, ignores distinct-name order, and retains repeated
value order and duplicates. Exact mode rejects unrelated names; subset mode
allows them while requiring the complete ordered values for every requested
name.

### Native escape hatch

`Fluffy.unwrap/2` is deliberately absent from the equivalence rows. It is one
public entry point to three driver-native APIs, not a portable behavior:
Static receives a `Plug.Conn`, LiveView receives a LiveViewTest `View`, and
Playwright receives a `Fluffy.Playwright.Handle`. Conformance checks only
the resulting state through ordinary shared assertions. Lifecycle and
listener-before-action behaviors remain owned by the named Fluffy APIs.
