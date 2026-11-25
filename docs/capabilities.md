# Capability matrix

The table compares Fluffy's Phoenix backend with Playwright, the reference, which
supports every feature not marked Phoenix only, within the boundaries described below. Each
`Fluffy.CapabilityError` names its feature's id in `Fluffy.Capability.matrix/0` as
`capability`.

- **equivalent** — matching behavior verified against Playwright;
- **structural subset** — supports HTML-represented state, with Playwright-only
  behavior excluded;
- **Phoenix only** — a Phoenix feature that Playwright has no counterpart for;
- **-** — unavailable or not applicable.

<!-- capability-matrix:start -->
| Feature | Phoenix |
| --- | --- |
| Frame locators and traversal | - |
| Conformance-tested CSS locators | equivalent |
| Text, label, and attribute locators | equivalent |
| Structural role and accessible-name subset | structural subset |
| Playwright action options | - |
| DOM assertions and strictness | equivalent |
| Page title assertions | equivalent |
| Page content and title, locator lists, and locator waits | structural subset |
| Indeterminate checkbox/radio DOM property | - |
| Focus, blur, and focus assertions | - |
| Structural element actions | structural subset |
| Visits, reloads, links, redirects, cookies, and HTTP forms | equivalent |
| Off-origin links, forms, and redirects | structural subset |
| Phoenix.HTML data-method/data-to actions | structural subset |
| LiveView events, patches, navigation, and structural action retry | equivalent |
| LiveView root layout, title updates, and portals | structural subset |
| LiveView form-change delivery and timing | structural subset |
| Declarative LiveView keyboard events | structural subset |
| Supported mutable form state and ordered submission | equivalent |
| Enter implicit form submission | - |
| Native constraint validation | - |
| Specialized scalar input values | structural subset |
| Computed style, layout, rendering, and browser accessibility tree | - |
| Downloads | equivalent |
| Multiple pages and new tabs | - |
| Browser history navigation | - |
| Adding, reading, and clearing cookies | equivalent |
| Browser storage: Web Storage reads and storage-state export and restoration | - |
| Browser and context options, permissions, geolocation, offline mode, and HTTP credentials | - |
| Hover, drag-and-drop, typing, keyboard, mouse, viewport, and media emulation | - |
| Dialogs, console, page errors, frames, workers, WebSockets, and browser network events | - |
| Browser request routing | - |
| Active-page JavaScript evaluation | - |
| Fake page clock and timers | - |
| JavaScript-owned DOM and default actions | - |
| Native invalid, submit, and formdata event ordering | - |
| Browser-dependent form entries and submissions | - |
| Native locators and download files | - |
| A prepared `Plug.Conn` for the first request | Phoenix only |
| Per-test sessions, cleanup, and Ecto sandbox propagation | equivalent |
| URL matching | equivalent |
| Typed file selection and supported upload lifecycle | equivalent |
| Script-opened file chooser events | - |
<!-- capability-matrix:end -->

## Boundaries

### When to choose Playwright

Use Playwright for computed style, layout, browser accessibility, native
validation, arbitrary JavaScript, and browser network events. Phoenix operates
on parsed HTML and mutable form state, and follows `Phoenix.LiveViewTest` where
that doesn't change what a test observes. Even Phoenix checks structural
visibility; see [Visibility and DOM presence](assertions.md#visibility-and-dom-presence)
for the distinction from browser rendering and DOM absence.

Phoenix locators do not model `<details>`, `<dialog>`, `popover` and dropdown
`<select>` open state, which a Phoenix test has no way to change: a click on a
`<summary>` doesn't toggle its `<details>` there, nor its `open` attribute. Content inside
a closed `<details>`, `<dialog>` or `popover`, and the options of a closed
`<select>`, count as visible on Phoenix, so a test can reach them without opening
them; on Playwright they must be opened first. A `refute` on that
content fails on Phoenix. Accessible names built from such content can differ
the same way.

Phoenix does not model `inert` either. On Playwright, actions wait while the
target or an ancestor is `inert`; on Phoenix they act on it.

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

As in LiveView's client, a render resets local text, select choices and
checkbox/radio state to the rendered ones per LiveView and LiveComponent: an
update to one resets them anywhere in it, including its portal content, but not
in other views, unchanged components or the root layout, so a title update
resets nothing. Checkboxes and radios reset even with focus or during their own
`phx-change`; selects reset because Playwright's `select_option` does not focus
them. A form during its `phx-trigger-action` handoff and content under
`phx-update="ignore"` keep their local state. A triggered form posts what was
typed into its text fields and textareas even when its trigger render drops it,
as the browser does. For its checkboxes, radios and selects, Static and LiveView
post what the trigger render shows, while the browser keeps the choices the user
made, since Fluffy doesn't track which controls the user changed.
The browser also keeps the typed value of a focused input or textarea through
any render that reaches it, its own `phx-change` reply or a later `handle_info`
alike, unless it has `phx-patch-focused` (LiveView's `mergeFocusedInput`, which
still applies the other attributes, such as `checked`). Unlike the browser,
Static and LiveView reset it to the rendered value, since they don't track focus:
render the form from the latest submitted params (`to_form(params)`), as
generated forms do, so both agree, or use Playwright for such a test.
Checkbox/radio state carries only to a control with the same type, name, and
value; a radio the server renders as newly checked clears its group. Files
survive while the matched control remains a file input with the same name. Elements
without an `id` are matched by position, so id-less controls with the same name
and value can still exchange state when a patch shifts them; give such controls
stable ids. Use Playwright for focused input protection, focus-sensitive
patches, blur or debounce timing, and exact browser patch behavior.

### Page content

`Fluffy.content/2` serializes the driver's document as a browser serializes its DOM:
the doctype, by name only, and the `<html>` element, with attributes as they are, so a
value typed into a field isn't there, as in the browser. It holds what the server
rendered, with LiveView's renders, `live_title` updates and portals applied, but not what
JavaScript changes in a browser, such as the `phx-connected` class LiveView's client adds.
A LiveView document has no whitespace-only text between elements, as LiveViewTest renders
it, and its `<title>` keeps the layout's whitespace until the title changes. Declarative
shadow roots stay `<template>` elements on Phoenix, while the browser leaves them out.
LazyHTML parses with scripting off, so markup inside `<noscript>` is parsed as elements and
comes out normalized on Phoenix, while the browser keeps it as raw text. To compare pages
across drivers, read or assert parts of them instead.

### LiveView document and patch boundaries

LiveView locators and actions see the full document: the dead-rendered root layout
with the current `Phoenix.LiveViewTest.View` render in place, `live_title` updates in
`<title>`, and portal content teleported into its target. As in the browser, root
layout bindings reach the main LiveView and portal bindings reach the LiveView that owns
the portal. Other LiveViews rendered in the root layout, such as sticky ones, are not
connected by LiveViewTest: they show their dead render, and actions on them raise
`Fluffy.CapabilityError`. LiveView-managed uploads inside portals require Playwright.
LiveView `Fluffy.unwrap/2` receives only the View.

LiveView follows a live navigation (`<.link navigate>` or `push_navigate`) over HTTP,
even within a `live_session`: the router's plugs run again, the root layout is
rendered again, losing local values in it, and the new view mounts disconnected
before it connects. A browser joins the new view over its open socket instead and
keeps the root layout. `Phoenix.LiveViewTest.live_redirect/2` needs the old view
still running, which `push_navigate` has already stopped, and drops the flash, so
Fluffy does not use it.

### Tabs, windows, and iframes

The Playwright backend exposes page handles for browser tabs and popup windows.
All public page-management helpers live in `Fluffy.Playwright` and reject Phoenix
sessions. Phoenix retains one current document internally; use shared page URL,
and title assertions to inspect it.
`Fluffy.Playwright.new_page/1` returns a handle; `Fluffy.Playwright.switch_page/2` selects it for subsequent actions.
Use [frame locators](locators.md#frames-playwright-only) to query iframe contents with
Playwright. Page switching does not select an iframe, and frame locators do not
change the active page.

On Phoenix, a link with `target="_blank"` opens in that one document, so a test can
still follow it; a click with `modifiers:` raises `Fluffy.CapabilityError`, as other
Playwright options do. A test that should behave the same on Playwright handles the new
tab there with `Fluffy.Event.popup/0`.

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

### Cookies

`Fluffy.add_cookies/2`, `Fluffy.cookies/2` and `Fluffy.clear_cookies/2` work on both
backends, with Playwright's cookie maps. A Phoenix session keeps its cookies in a jar, as a
browser context does, which follows RFC 6265 for domains, paths, `Secure` and expiry; every
request sends what it holds then, the LiveView mount's included. Its requests stay on the
app's origin, so it does not enforce `SameSite`, and it ignores `partitionKey`. A cookie
set without `SameSite` reports `"Lax"`, as Chromium does (Firefox reports `"None"`). An
invalid cookie raises `ArgumentError` with Playwright's message, and a key that is no cookie
field, such as `http_only:` for `httpOnly:`, with PlaywrightEx's, on both backends.

### Before the first visit

A Playwright session starts at `about:blank`, where an action waits for its element until it
times out. A Phoenix session has no page until its first `visit`: page operations (actions,
expectations, `reload`, `unwrap`, `open_browser`) raise `ArgumentError` at once. Cookie
functions work before it, as a login flow needs. `Fluffy.Playwright` calls and Playwright-only
options raise `Fluffy.CapabilityError`, as on any Phoenix page.

### Leaving the app

Phoenix stays in the app. A link, form or redirect to another origin, including a LiveView
`redirect(socket, external: url)`, ends at a page with only that URL, without requesting it,
so a test can assert where the app sent it, as with `Phoenix.ConnTest.redirected_to/1`:

```elixir
session
|> click(by_role(:button, name: "Floo to the Ministry"))
|> expect(page_to_have_url(~r"^https://ministry\.example/floo\?"))
```

Only URL expectations and `visit` back into the app work on that page; everything else raises
`Fluffy.CapabilityError` (`:external_navigation`), as does `visit` to another origin. Use
`page_to_have_url`, since `assert_path` ignores the host. On Playwright the browser loads the external page; stub it with
`Fluffy.Playwright.route/4`, which catches a link's or form's target but not a redirect's.

### Browser baseline

Fluffy's conformance suite runs against Playwright's pinned Chromium, Firefox,
and WebKit. Known engine differences: WebKit does not send `Secure` cookies to
`http://` loopback origins, and submits the controls in the legend of a disabled
`<fieldset>` nested in another disabled one. Firefox doesn't click on through a label whose
control sits in another label, where Chromium and WebKit click each label's control once.
Firefox never completes or fails an interrupted
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
cancellation path is part of the assertion. Static and LiveView both model the pinned
Phoenix.HTML `data-method`/`data-to` hidden-form action for plain elements, including
links and buttons. Custom `phoenix.link.click` listeners, cancellation, and competing
LiveView actions remain Playwright only.

### Forms and files

Static and LiveView bypass native validation and retain specialized scalar
input values as supplied strings. Use Playwright for validation events and
blocking, browser sanitization/defaults, and custom or form-associated elements.

Native reset-button behavior requires Playwright. Static and LiveView clicks do
not restore form defaults or clear file selections. LiveView reset buttons with
`phx-click` still dispatch their server event.

A LiveView click sends the closest `phx-click`, the target's or an ancestor's,
and then takes the default action of the closest button or link, as a browser
does: a submit button submits its form and a link is followed. Only `href="#"`
and LiveView links prevent it. The form is submitted as the click found it,
before the event's render. `Phoenix.LiveViewTest.render_click/2` sends only the
event.

On Phoenix, a click or key event sends a form control's current `value` and a
list item's number; other elements send no `value`, while a browser also sends
one for `meter`, `progress`, `output`, `data` and `param`.

As in LiveView's client, the LiveView driver submits a form the view renders with
`phx-trigger-action`, but a pushed render's form only when it next reads the view,
as an action or expectation does; an action whose target is already there acts on
the last read document first. It looks for the form in the whole document, while
the client only looks in the LiveView it patches. The submission counts toward the
20-redirect limit of the redirects that led there, where a browser starts a fresh
count, so a view whose form leads back to it fails instead of looping.

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
[Native escape hatch](debugging.md#native-escape-hatch) for callback behavior.

### Playwright coverage

Fluffy classifies every member of the Playwright facade it builds on, and a test
fails when Playwright adds or removes one.

- **Wrapped:** locator builders (`get_by_role` as `by_role`, and so on), the
  cross-driver actions, including `clear` and `set_checked`, the locator reads
  `text_content`, `get_attribute`, `input_value`, `all_text_contents`, `inner_text`
  and `all_inner_texts`, `hover`, `drag_to`,
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
  HTTP credentials, extra HTTP headers, request routing, including `unroute_all`,
  tracing, page and element screenshots, page evaluation, init scripts, script and
  style tags, `wait_for_function` and `wait_for_load_state` on the page, the clock in
  `Fluffy.Playwright.Clock`, keyboard and mouse input in `Fluffy.Playwright.Keyboard`
  and `Fluffy.Playwright.Mouse`, the events in `Fluffy.Event`, and the values they
  deliver, including response bodies. Their options pass through as documented.
  `to_have_screenshot` and `to_match_aria_snapshot` (without an inline snapshot) find
  their file by `name:` or the test's name, through `Playwright.Test`, or at `path:`.
- **Unwrap:** everything else page-, locator-, or value-local, such as
  `aria_snapshot_json`, HAR routing, and response timing. For reads like
  `inner_html` or `is_visible`, `Fluffy.unwrap_and_return/2` and
  `Fluffy.Playwright.unwrap_and_return/3` return the callback's result instead of
  the session. Navigation these cause is adopted.
- **Unsafe natively:** closing the page or context (use `Fluffy.Playwright.close_page/2`
  and `Fluffy.close_session/1`), `remove_all_listeners`, `set_default_timeout` and
  `set_default_navigation_timeout`, the `no_wait_after:` and `signal:` options,
  `set_content`, and stopping tracing. They break Fluffy's page tracking,
  listeners, or timeouts.
- **Not applicable:** selector-string duplicates of locator methods, deprecated
  waits, and authoring tools.
