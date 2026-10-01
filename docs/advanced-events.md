# Events and pages

Register before the triggering action, then await an ordinary value:

```elixir
use Fluffy.Assert
import Fluffy
import Fluffy.Locator
alias Fluffy.{Dialog, Download, Event, FileChooser, Frame, Page}

pending = wait_for(session, Event.download())
click(session, by_role(:button, name: "Download report"))
download = await(pending)
assert download.suggested_filename == "report.csv"
assert Download.read!(download) =~ "customer_id,total"
```

Each wait has an independent source, predicate, and deadline. The deadline starts
at registration, using the session timeout unless `timeout:` is supplied. Await
once; reuse the returned value freely. Separate waits can observe the same event.
A settled event outcome survives subsequent timeout or source closure. A still-pending
wait reports timeout, page closure, or session closure through `await`.

Constructors accept an optional unary predicate. False and nil skip an event;
predicate failures propagate through `await`. Keep predicates short and inspect
available metadata. Use ordinary assertions when failure details matter.

## Pipeline expectations

`assert_event` and `Fluffy.Expect.expect_event` register before invoking the action,
await a matching event, optionally inspect it, and return the input session:

```elixir
session
|> assert_event(
  Event.download(&(&1.suggested_filename == "report.csv")),
  &click(&1, by_role(:button, name: "Download report")),
  fn download -> assert Download.read!(download) =~ "customer_id,total" end,
  timeout: 5_000
)
|> click(by_role(:button, name: "Continue"))
```

The assertion callback and options are optional. With four arguments, pass either
an assertion callback or options. Both callbacks run once in the caller process;
their return values are ignored. Actions update shared state, while the enclosing
pipeline retains its original page selection. The helper releases its registration
on every exit and preserves callback errors.

## Downloads

A download handle exposes `suggested_filename` and `url` when downloading starts.
`Download.read!(download, max_bytes: 10_000_000)` waits for completion and returns
bytes, enforcing the indicated in-memory limit (10 MB by default).
`Download.save_as!(download, destination)` waits and saves using bounded memory.
Failures raise when reading or saving. Handles belong to their session; saved
files outlive it. In-process HTTP downloads use the same API. JavaScript-generated
downloads require Playwright.

## Pages, popups, and frames

A page is a browser tab or window. A popup is a page opened by another page;
ordinary `target="_blank"` tabs count. Each browser context owns a session's
cookies and storage. Frames are documents inside a page, including its main frame
and any child iframes.

`Event.popup()` observes pages opened by the selected page at registration.
`Event.page()` observes any new page in the context. Both may return handles for
the same physical page. The event resolves immediately; the page may still be
loading. Subsequent actions and assertions handle readiness.

```elixir
main = current_page(session)
pending = wait_for(session, Event.popup())
click(session, by_role(:link, name: "Open report"))
report = await(pending)

session
|> switch_page(report)
|> assert(page_opener(main))
|> assert(page_url(path: "/reports/preview"))
|> close_page()
|> switch_page(main)
```

Inspect live page handles with `Page.url/1`, `Page.status/1`, and `Page.opener/1`.
The opener is nil if absent or closed. `current_page/1` returns a stable handle
that survives navigation; `pages/1` lists all open pages, including tabs discovered
without an event registration.
Page selection is local to each session handle: retain the result of
`switch_page/2`; other session handles keep their own selection.
Closed page handles are invalid; closing a page does not change any session
handle's selection. Explicitly switch to an open
page before continuing. Closing an opener leaves its child pages alive.

`new_page(session, :dashboard)` creates and selects a named blank page.
`switch_page/2` accepts handles or names. Pages share cookies and storage; start
another session for an independent user. Phoenix follows links and submits forms
in the current page, ignoring `target` and `formtarget`; page creation and closing
require Playwright.

Frame locators query iframe contents without switching pages. Browser-only
`Event.frame_navigated()` observes navigation of any frame belonging to the page
bound at registration, including frames created later. It returns a live frame
handle: `Frame.url/1`, `Frame.page/1`, and `Frame.parent_frame/1` expose current
metadata. The main frame has no parent. Navigation events signal frame navigation,
not loading completion.

For navigation outcomes on either backend, use ordinary page assertions:

```elixir
session
|> click(by_role(:link, name: "Continue"))
|> assert(page_url(path: "/next"))
|> assert(page_status(200))
```

`go_back/2` and `go_forward/2` require Playwright and accept `timeout:`. For
reloading either backend, see [Reloading](usage.md#reloading).
`close_session/1` releases session resources on either backend.

## Listeners and dialogs

`on(session, event, handler)` registers a persistent listener. `once` removes its
registration before invoking the first matching handler; it does not require an
event to occur. All three listener operations return the input session.
`off(session, event, handler)` removes only the most recent registration matching
the source, event type, and handler; the predicate does not affect removal.
Repeated registrations require repeated removal calls.

Each listener handles matching events in delivery order. Different listeners run
independently; relative ordering is unspecified. Handlers and predicates execute
outside the session runtime and browser connection, linked to the registering
caller so unhandled failures fail that caller. Registration completes before
returning. Listeners have no deadline and are cleaned up when removed or when
their owner or session closes.

Dialogs require Playwright. Handle them on arrival because an unresolved dialog
blocks the triggering action:

```elixir
session
|> once(Event.dialog(), fn dialog ->
  assert dialog.type == :confirm
  assert dialog.message == "Delete this item?"
  Dialog.accept(dialog)
end)
|> assert_event(Event.dialog(), &click(&1, by_role(:button, name: "Delete")))
```

Use `Dialog.accept(dialog, "prompt text")` for prompts or `Dialog.dismiss(dialog)`.
Types are `:alert`, `:confirm`, `:prompt`, and `:beforeunload`; metadata also includes
`message` and `default_value`. Register a persistent catch-all handler when needed:

```elixir
accept_dialog = &Dialog.accept/1
session
|> on(Event.dialog(), accept_dialog)
|> click(by_role(:button, name: "Delete first item"))
|> click(by_role(:button, name: "Delete second item"))
|> off(Event.dialog(), accept_dialog)
```

Without dialog listeners or waits, Playwright dismisses dialogs automatically.
Once registered, handlers must resolve dialogs; a rejected predicate leaves the
dialog unresolved. A wait observes without accepting or dismissing. Independent
handlers and waits can observe the same dialog; ensure only one handler resolves it.

## Requests and responses

Request and response events require Playwright. Page scope, the default, includes
child frames; `scope: :context` observes all pages, including a popup's first request.
Sources remain bound when switching pages. Use the same source and scope for `off`.
Other events reject `scope:`: page events always observe the context, while popup,
download, dialog, chooser, and frame-navigation events bind to the selected page.

```elixir
session
|> assert_event(
  Event.response(&String.ends_with?(&1.url, "/api/reports")),
  &click(&1, by_role(:button, name: "Refresh")),
  fn response -> assert response.status == 200 end,
  scope: :context
)
```

Requests signal issuance; responses signal status and headers, without waiting for
the response body. Values expose URL, method, headers, resource type, post data,
page, and response status fields where applicable. The page can be nil when it
is not yet known, such as for a popup's initial request.

## File choosers

Locate a file input directly when possible, including hidden inputs. For a button
whose JavaScript opens a chooser, register first and pass the returned value directly:

```elixir
pending = wait_for(session, Event.file_chooser())
click(session, by_role(:button, name: "Choose portrait"))
chooser = await(pending)
assert FileChooser.multiple?(chooser) == false
set_input_files(session, chooser, "test/support/fixtures/portrait.png")
```

The chooser identifies its source page. Setting files preserves the current-page
selection, even after switching elsewhere. This sets files programmatically; it
does not operate the OS picker. Choosers require Playwright.

## Cookies, storage, and browser interactions

`Fluffy.Playwright.add_cookies/2` and `clear_cookies/2` return the session.
`cookies/2` returns cookie maps; its optional `urls:` list filters by URL.
`clear_cookies/2` accepts string or regex filters for `name:`, `domain:`, and
`path:`. These helpers operate on the entire browser context.

`Fluffy.Playwright.storage_state/2` returns a state map and optionally writes
JSON with `path:`. Include IndexedDB with `indexed_db: true`. Reuse the result
with `start_session(:playwright, browser_context: [storage_state: state])`.

For browser interaction, use `hover(session, locator)`,
`drag_to(session, source, target)`, or
`press_sequentially(session, locator, text, delay: 20)`. All accept `timeout:`.
Sequential typing emits keyboard events for each character and appends at the
current caret position. Drag source and target must belong to the same frame.
These actions require Playwright and reconcile navigation caused by the action.
