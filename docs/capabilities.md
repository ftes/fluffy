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
| Documented CSS locator subset | equivalent | equivalent |
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
| Named pages and new tabs | - | equivalent |
| Browser history navigation | - | equivalent |
| Browser cookie helpers and storage-state export | - | equivalent |
| Hover, drag-and-drop, and sequential typing | - | equivalent |
| Dialogs, frame navigation, and browser request/response events | - | equivalent |
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
  that a keydown removing the LiveComponent handling the key loses the keyup.
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
require Playwright. Static and LiveView do not track or simulate focus.

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
give such controls stable ids. Use Playwright for focused input protection and exact browser patch
behavior.

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

Static and LiveView can query the iframe element in their current markup, but
do not load its `src` or parse its `srcdoc` as a child document. They do not
flatten iframe contents into the parent document or ignore frame boundaries:
executing a frame-traversing query raises `Fluffy.CapabilityError`. Visit the
embedded route directly to test it independently with Phoenix; use Playwright
to test the embedding behavior. See
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
cancellation, replacement, auto-upload, and submission.

The LiveView change event sent when files are selected for a managed upload
carries LiveViewTest's serialization of the rendered form: server-rendered
values and no `_unused_` params, so every field reads as used. Use Playwright
when a test depends on `used_input?` or on local text the server has not
rendered at the time files are selected.

Native picker UI, external uploaders, directories, drag-and-drop, and arbitrary
`FileList` mutation are unsupported. `Fluffy.Event.file_chooser/1` requires Playwright
because application JavaScript opens the chooser.

### Native escape hatch

`Fluffy.unwrap/2` exposes driver-specific APIs: `Plug.Conn`,
`Phoenix.LiveViewTest.View`, or `PlaywrightEx.Page`. `Fluffy.Playwright.unwrap/3`
passes a `PlaywrightEx.Locator`. Use the shared event and page APIs for lifecycle
operations. See [Native escape hatch](usage.md#native-escape-hatch) for callback
behavior.

### PlaywrightEx coverage

Fluffy classifies every member of the PlaywrightEx facade it builds on, and a test
fails when PlaywrightEx adds or removes one.

- **Wrapped:** locator builders (`get_by_role` as `by_role`, and so on), the
  cross-driver actions, `hover`, `drag_to`, `press_sequentially`, `focus`, `blur`,
  the expectations in `Fluffy.Expect`, navigation, page management, cookies,
  storage state, tracing, screenshots, page evaluation, the clock in
  `Fluffy.Playwright.Clock`, and the events in `Fluffy.Event`. Their options pass
  through as documented.
- **Unwrap:** everything page-, locator-, or value-local, such as `dblclick`, reads
  like `text_content`, assertions like `to_have_text`, keyboard and mouse input,
  routing, viewport, media emulation, permissions, and response bodies. Navigation
  these cause is adopted.
- **Unsafe natively:** closing the page or context (use `Fluffy.Playwright.close_page/2`
  and `Fluffy.close_session/1`), `remove_all_listeners`, `set_default_timeout` and
  `set_default_navigation_timeout`, the `no_wait_after:` and `signal:` options,
  `set_content`, and stopping tracing. They break Fluffy's page tracking,
  listeners, or timeouts.
- **Not applicable:** selector-string duplicates of locator methods, deprecated
  waits, and authoring tools.
