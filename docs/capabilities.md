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
| Frame locators and traversal | - | equivalent |
| Conformance-tested CSS locators | equivalent | equivalent |
| Text, label, and attribute locators | equivalent | equivalent |
| Structural role and accessible-name subset | structural subset | equivalent |
| Role-state and regular-expression locator options | - | equivalent |
| Playwright action options | - | equivalent |
| DOM assertions and strictness | equivalent | equivalent |
| Page title assertions | equivalent | equivalent |
| Indeterminate checkbox/radio DOM property | - | equivalent |
| Focus, blur, and focus assertions | - | equivalent |
| Structural element actions | structural subset | equivalent |
| Visits, reloads, links, redirects, cookies, and HTTP forms | equivalent | equivalent |
| Phoenix.HTML data-method/data-to actions | structural subset | equivalent |
| LiveView events, patches, navigation, and structural action retry | equivalent | equivalent |
| LiveView root layout, title updates, and portals | structural subset | equivalent |
| LiveView form-change delivery and timing | structural subset | equivalent |
| Declarative LiveView keyboard events | structural subset | equivalent |
| Supported mutable form state and ordered submission | equivalent | equivalent |
| Enter implicit form submission | - | equivalent |
| Native constraint validation | - | equivalent |
| Specialized scalar input values | structural subset | equivalent |
| Computed style, layout, and browser accessibility tree | - | equivalent |
| Downloads | equivalent | equivalent |
| Multiple pages and new tabs | - | equivalent |
| Browser history navigation | - | equivalent |
| Browser cookie helpers and storage-state export | - | equivalent |
| Runtime permissions, geolocation, offline mode, and HTTP credentials | - | equivalent |
| Hover, drag-and-drop, sequential typing, keyboard, and mouse input | - | equivalent |
| Dialogs, console, page errors, frames, workers, WebSockets, and browser network events | - | equivalent |
| Browser request routing | - | equivalent |
| Active-page JavaScript evaluation | - | equivalent |
| Fake page clock and timers | - | equivalent |
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

Phoenix locators do not model `<details>`, `<dialog>`, `popover` and dropdown
`<select>` open state, which a Phoenix test has no way to change. Content inside
a closed `<details>`, `<dialog>` or `popover`, and the options of a closed
`<select>`, count as visible on Phoenix, so a test can reach them without opening
them; on Playwright they must be opened first. A `refute` on that
content fails on Phoenix. Accessible names built from such content can differ
the same way.

### LiveView timing and keyboard events

LiveView eagerly dispatches each applicable form-control `phx-change` and
ignores `phx-debounce`/`phx-throttle` scheduling, including `phx-debounce="blur"`.
Phoenix does not model focus; its change delivery is independent of focus. Use
Playwright for delay, blur-only delivery, coalescing, cancellation, and throttle
suppression.

`Fluffy.press/4` has a driver-specific contract:

- **Static:** unsupported; raises `Fluffy.CapabilityError` for every key.
- **LiveView:** passes the supplied key unchanged to LiveViewTest keydown/keyup
  handlers bound to the selected element. This includes window bindings on that
  element, without discovering handlers elsewhere in the document. Event values
  and targeting follow LiveViewTest. Keyup uses the binding the element had when
  the press started, even if the keydown's patch changes or removes it, except
  that a keydown removing the LiveComponent handling the key loses the keyup
  (`@myself`) or sends it to the view (CSS selector).
  Fluffy does not apply `phx-key` filters, translate keys or modifier
  combinations, synthesize field values, or simulate focus movement, editing,
  activation, or implicit submission. An element with no keyboard binding
  raises. Callers supply the intended key value.
- **Playwright:** native browser key presses, including default actions and
  Playwright modifier syntax.

Filling contenteditable elements requires Playwright. Static and LiveView fill
input and textarea controls; they do not emulate editing element text.

### Focus and client state

`Fluffy.Playwright.focus/3`, `Fluffy.Playwright.blur/3`, and focus assertions
require Playwright; with `import Fluffy.Playwright`, call `focus` and `blur` directly.
Static and LiveView track current input properties but neither track nor simulate focus.

On a changed LiveView render, local text values adopt the rendered value,
except during `phx-trigger-action` handoff. Unchanged document renders preserve
local values. Changes are detected across the document, not per control, so an
unrelated update can discard local text. Checkbox/radio state survives while the
rendered `checked` attribute is unchanged and the matched control keeps its type,
name, and value; a radio the server renders as newly checked clears its group.
Selected options survive while the select name and option signature are
unchanged; files survive while the matched control remains a file input with the
same name. Elements without an `id` are matched by position, so id-less controls
with the same name and value can still exchange state when a patch shifts them;
give such controls stable ids. Use Playwright for focused input protection,
focus-sensitive patches, blur or debounce timing, and exact browser patch behavior.

### LiveView document and patch boundaries

LiveView locators and actions see the full document: the dead-rendered root layout
with the current `Phoenix.LiveViewTest.View` render in place, `live_title` updates in
`<title>`, and portal content teleported into its target. As in the browser, root
layout bindings reach the main LiveView and portal bindings reach the LiveView that owns
the portal. Other LiveViews rendered in the root layout, such as sticky ones, are not
connected by LiveViewTest: they show their dead render, and actions on them raise
`Fluffy.CapabilityError`. LiveView-managed uploads inside portals require Playwright.
LiveView `Fluffy.unwrap/2` receives only the View.

### Tabs, windows, and iframes

The Playwright backend exposes page handles for browser tabs and popup windows.
All public page-management helpers live in `Fluffy.Playwright` and reject Phoenix
sessions. Phoenix retains one current document internally; use shared page URL,
and title assertions to inspect it.
`Fluffy.Playwright.new_page/1` returns a handle; `Fluffy.Playwright.switch_page/2` selects it for subsequent actions.
Use [frame locators](usage.md#frames-playwright) to query iframe contents with
Playwright. Page switching does not select an iframe, and frame locators do not
change the active page.

Static works on the response HTML and LiveView on its rendered document. Both can
query an iframe element and its attributes, but do not load its `src` or parse its
`srcdoc` as a child document, so ordinary locators cannot find elements inside it.
They do not flatten iframe contents into the parent document or ignore frame boundaries:
executing a frame-traversing query raises `Fluffy.CapabilityError`. Visit the
embedded route directly to test it independently with Phoenix; use Playwright
to test the embedding behavior, including interactions between the parent page and
iframe. See
[Pages, popups, and frames](advanced-events.md#pages-popups-and-frames)
for how pages, browser contexts, and frames relate.

### Browser baseline

Fluffy's conformance suite runs against Playwright's pinned Chromium, Firefox,
and WebKit. Known engine differences: WebKit does not send `Secure` cookies to
`http://` loopback origins. Firefox never completes or fails an interrupted
download, and with Playwright 1.65 a file chooser awaited right after an earlier
one occasionally opens a native dialog instead.
Playwright's `set_input_files` checks only that the target is an `<input>`:
Firefox and WebKit, and in-memory payloads on every engine, accept a non-file
input without an error and select nothing, and Chromium rejects a path only
after the action timeout. Static and LiveView raise `Fluffy.ActionabilityError`
with reason `:not_file_input`, so run file selection on Static or LiveView too
to catch a locator that matches the wrong input.

### Phoenix.HTML actions and dialogs

For a Static or LiveView target with `data-confirm`, `Fluffy.click/2` ignores the
attribute and continues with the normal structural action. It does not create, inspect,
accept, or dismiss a browser dialog; use Playwright whenever the prompt or its
cancellation path is part of the assertion. Both in-process drivers model the pinned
Phoenix.HTML `data-method`/`data-to` hidden-form action for plain elements, including
links and buttons. Custom `phoenix.link.click` listeners, cancellation, and competing
LiveView actions remain browser-only.

### Forms and files

Static and LiveView bypass native validation and retain specialized scalar
input values as supplied strings. Use Playwright for validation events and
blocking, browser sanitization/defaults, and custom or form-associated elements.

Native reset-button behavior requires Playwright. Static and LiveView clicks do
not restore form defaults or clear file selections. LiveView reset buttons with
`phx-click` still dispatch their server event.

File selection supports bounded local paths and typed in-memory payloads,
ordered multiple selection, clearing, and ordinary multipart forms, including
empty-file entries. Managed LiveView uploads support validation, progress,
cancellation, replacement, auto-upload, and submission. Their form needs an id,
as LiveView's form recovery does: LiveView `set_input_files` raises without one.

The LiveView change event sent when files are selected for a managed upload
carries LiveViewTest's serialization of the rendered form: server-rendered
values and no `_unused_` params, so every field reads as used. Use Playwright
when a test depends on `used_input?` or on local text the server has not
rendered at the time files are selected.

Native picker UI, external uploaders, directories, drag-and-drop, and arbitrary
`FileList` mutation are unsupported. `Fluffy.Event.file_chooser/1` requires Playwright
because application JavaScript opens the chooser.

### Native escape hatch

`Fluffy.unwrap/2` and `Fluffy.unwrap_and_return/2` reach driver-native APIs; see
[Native escape hatch](usage.md#native-escape-hatch) for callback behavior.

### PlaywrightEx coverage

Fluffy classifies every member of the PlaywrightEx facade it builds on, and a test
fails when PlaywrightEx adds or removes one.

- **Wrapped:** locator builders (`get_by_role` as `by_role`, and so on), the
  cross-driver actions, including `clear` and `set_checked`, `hover`, `drag_to`,
  `press_sequentially`, `focus`, `blur`, `dblclick`, `tap`, `dispatch_event`,
  `select_text`, `scroll_into_view_if_needed`, `wait_for` on a locator,
  `bounding_box`, `aria_snapshot`, `drop`, `all`, `Fluffy.Locator.within/2`, locator
  `evaluate`, `evaluate_all` and `wait_for_function`, `set_viewport_size`,
  `viewport_size`, `emulate_media`, `pdf`, `bring_to_front`, `content`, `title`,
  the expectations in `Fluffy.Expect`, including `to_have_css`,
  `to_have_js_property`, `to_have_role`, the accessible name, description and error
  message assertions, `to_match_aria_snapshot` and `to_have_screenshot`, navigation,
  page management, cookies, storage state, including `set_storage_state`,
  `local_storage` and `session_storage`, permissions, geolocation, offline mode,
  HTTP credentials, extra HTTP headers, request routing, including `unroute_all`
  and `Fluffy.Route.fetch/2`,
  tracing, page and element screenshots, page evaluation, init scripts, script and
  style tags, `wait_for_function` and `wait_for_load_state` on the page, the clock in
  `Fluffy.Playwright.Clock`, keyboard and mouse input in `Fluffy.Playwright.Keyboard`
  and `Fluffy.Playwright.Mouse`, the events in `Fluffy.Event`, and the values they
  deliver, including response bodies. Their options pass through as documented.
  `to_have_screenshot` needs an explicit `path:` for its baseline, which Fluffy does
  not derive from the test name; `to_match_aria_snapshot` compares an inline snapshot
  or, with `path:`, a file written when missing.
- **Unwrap:** everything else page-, locator-, or value-local, such as
  `aria_snapshot_json`, HAR routing, and response timing. For reads like
  `text_content`, `Fluffy.unwrap_and_return/2` and
  `Fluffy.Playwright.unwrap_and_return/3` return the callback's result instead of
  the session. Navigation these cause is adopted.
- **Unsafe natively:** closing the page or context (use `Fluffy.Playwright.close_page/2`
  and `Fluffy.close_session/1`), `remove_all_listeners`, `set_default_timeout` and
  `set_default_navigation_timeout`, the `no_wait_after:` and `signal:` options,
  `set_content`, and stopping tracing. They break Fluffy's page tracking,
  listeners, or timeouts.
- **Not applicable:** selector-string duplicates of locator methods, deprecated
  waits, and authoring tools.
