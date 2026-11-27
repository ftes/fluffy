# Advanced events and pages

Use `assert_event` to check what an action triggered. Use `wait_for` and `await`
when you need the value afterwards, for example to switch to a popup. With the
setup from [Your first test](usage.md#your-first-test), add:

```elixir
import Fluffy.Playwright
alias Fluffy.{Download, Event, FileChooser}
```

## Pipeline expectations

Assert that clicking the map button starts a download, then check its contents.
`assert_event` registers before the click so it catches even an immediate download:

```elixir
session
|> assert_event(
  Event.download(),
  &click(&1, button("Download the Marauder's Map")),
  fn download ->
    assert download.suggested_filename == "marauders_map.csv"
    assert Download.read(download) =~ "student,house"
  end
)
|> click(button("Continue"))
```

Omit the final callback if the event alone is enough. Options such as `timeout:`
can follow either callback. The action runs once in the caller. If the action
succeeds and the event matches, the assertion callback runs once there too.
Return values are ignored. The pipeline keeps its page selection, even if the action
switches pages. Callback failures propagate and the registration is released.

## Capture an event value

Register just before the action, then await once. You can reuse the returned
value, for example to save a download outside the session:

```elixir
pending = wait_for(session, Event.download())
click(session, button("Download the Marauder's Map"))
map = await(pending)
Download.save_as(map, "marauders_map.csv")
```

The deadline starts at registration. Unless you pass `timeout:`, it uses the
browser's action timeout or Phoenix's short `phoenix_backend_timeout`
([Configuration](installation.md#configuration)). Separate waits can match the
same event. An already settled result survives timeout or page or session closure;
`await` reports those failures for a wait that was still pending.

Use an event predicate to select among several events, then assert on the
matched value for a useful failure message. A false or nil predicate skips an
event; a raised error propagates through `await`.

## Downloads

A download handle exposes `suggested_filename` and `url` when downloading starts.
`Download.read(download, max_bytes: 10_000_000)` waits for completion and returns
bytes, enforcing the indicated in-memory limit (10 MB by default).
`Download.save_as(download, destination)` waits and saves using bounded memory.
Failures raise when reading or saving; on Playwright, `Fluffy.unwrap_and_return/2` reaches
`failure` and `cancel` on the `Playwright.Download` (see
[Native escape hatch](debugging.md#native-escape-hatch)). Handles belong to their
session; saved files outlive it. In-process HTTP downloads use the same API and
complete before delivery. `Fluffy.Download.path/1` returns the browser's copy of the file:
Phoenix holds the bytes in memory and raises `Fluffy.CapabilityError`.
JavaScript-generated downloads require Playwright.

## Pages, popups, and frames

To follow a `target="_blank"` link in Playwright, remember the opener and wait
for its popup. The event can arrive before the new page finishes loading; assert
on the page after switching to it:

```elixir
main = current_page(session)
pending = wait_for(session, Event.popup())
click(session, link("Open the Daily Prophet"))
prophet = await(pending)

session
|> switch_page(prophet)
|> assert(page_opener(main))
|> assert(page_url("/prophet/preview"))
|> close_page()
|> switch_page(main)
```

`Event.popup()` watches the page selected at registration; `Event.page()` watches
the whole context. Both can report the same tab. `pages(session)` lists open tabs
even without a wait. A page handle survives navigation; read its current URL or
opener with `Fluffy.Page.url/1` or `Fluffy.Page.opener/1`.

Keep the result of `switch_page` when you want to keep acting in that tab. Each
session handle keeps its own selection. Closing a page invalidates its page
handle without selecting another tab. Its children stay open, with a nil opener.

As in Playwright, an action that closes its own page succeeds, except on Firefox, which
fails it with a closed-page error. `Event.close()` resolves with the selected
page's handle once it closes, by its own script or `Fluffy.Playwright.close_page/2`.
For a popup that closes itself, sign the slip **instead of** calling `close_page()`:

```elixir
session
|> switch_page(prophet)
|> assert_event(Event.close(), &click(&1, button("Sign permission slip")))
|> switch_page(main)
```

`Fluffy.Playwright.new_page(session)` returns a new blank page handle without changing the session's
selection. Pass that handle to `Fluffy.Playwright.switch_page/2` or `Fluffy.Playwright.close_page/2`:

```elixir
main = current_page(session)
common_room = new_page(session)

session
|> switch_page(common_room)
|> visit("/common-room")
|> close_page(common_room)
|> switch_page(main)
```

Pages share cookies and storage; start another session for an independent user.
Phoenix follows links and submits forms in the current page,
ignoring `target` and `formtarget`; page creation and closing require Playwright.

Frame locators query iframe contents without switching pages. Playwright-only
`Event.frame_navigated()` observes navigation of any frame belonging to the page bound
at registration, including frames created later. It resolves with the
`Playwright.Frame`, whose `url/1`, `page/1` and `parent_frame/1` read current
metadata. The main frame has no parent. Navigation events signal frame
navigation, not loading completion.

For navigation outcomes on either backend, use ordinary page assertions:

```elixir
session
|> click(link("Continue"))
|> assert(page_url("/next"))
```

`Fluffy.Playwright.go_back/2` and `Fluffy.Playwright.go_forward/2` require Playwright and accept the
options of `Playwright.Page.go_back/2`.
For reloading either backend, see [Reloading](actions.md#reloading).
`Fluffy.close_session/1` releases session resources on either backend.

## Listeners and dialogs

To confirm a browser dialog, register a listener that answers it **during** the
click. A wait alone would leave the click blocked. `once` handles the next match;
`assert_event` separately checks that the dialog actually appeared:

```elixir
alias Playwright.Dialog

session
|> once(Event.dialog(), fn dialog ->
  assert Dialog.type(dialog) == "confirm"
  assert Dialog.message(dialog) == "Vanish this potion?"
  Dialog.accept!(dialog)
end)
|> assert_event(Event.dialog(), &click(&1, button("Vanish")))
```

Use `Dialog.accept!(dialog, "prompt text")` for prompts or `Dialog.dismiss!(dialog)`.
`Fluffy.Playwright.page/2` turns the `Dialog.page/1` that opened it, or any other
`Playwright.Page` of the session, into a `Fluffy.Page` for `switch_page/2`; a dialog
without a page gives `nil`, which it returns. Register
a persistent catch-all handler when needed:

```elixir
accept_dialog = &Dialog.accept!/1
session
|> on(Event.dialog(), accept_dialog)
|> click(button("Vanish first potion"))
|> click(button("Vanish second potion"))
|> off(Event.dialog(), accept_dialog)
```

Without dialog listeners or waits, Playwright dismisses dialogs automatically.
Once registered, handlers must resolve dialogs; a rejected predicate leaves the
dialog unresolved. A wait observes without accepting or dismissing. Independent
handlers and waits can observe the same dialog; ensure only one handler resolves it.

`on`, `once` and `off` return the session. Registration completes before the
next action. `once` unregisters before invoking its handler; `off` removes the
latest registration with the same source, event type and handler, ignoring its
predicate. Listeners have no deadline and end when removed or their owner or
session closes.

Each listener receives matches in order; separate listeners run independently.
Handlers and predicates run outside the session runtime and browser connection,
linked to the caller so unhandled errors fail the test. They inherit `$callers`
for sandbox queries and mocks.

## Requests and responses

To check what the Daily Prophet API returned, select the response by URL and
assert on its status. Use `scope: :context` to catch requests from any tab,
including a popup's first request:

```elixir
alias Playwright.Response

session
|> assert_event(
  Event.response(&String.ends_with?(Response.url(&1), "/api/prophet")),
  &click(&1, button("Refresh")),
  fn response ->
    assert Response.status(response) == 200
    assert Response.json!(response)["title"] == "Evening Edition"
  end,
  scope: :context
)
```

Network events require Playwright. By default they watch the selected page
and its child frames. Switching pages doesn't move a registration; use the
original source and scope for `off`. Only request, response, request-failed
and request-finished events accept `scope:`.

Requests signal issuance; responses signal status and headers, without waiting for
the response body. The values are a `Playwright.Request` and a `Playwright.Response`;
read them with Playwright's functions. Reading the body with `Response.json!/1`
waits for the response to end and takes no timeout.

`Event.request_failed()` and `Event.request_finished()` resolve with the request
once it fails or its response body has downloaded. An HTTP error status is a
finished request, not a failed one. In a request-failed event callback,
`Playwright.Request.failure/1` gives the failure reason as `%{errorText: reason}`.

## Console, page errors, and page lifecycle

These events require Playwright and observe the page selected at registration,
including its child frames.

```elixir
alias Playwright.ConsoleMessage

session
|> assert_event(
  Event.console(&(ConsoleMessage.type(&1) == "error")),
  &click(&1, button("Refresh")),
  fn message -> assert ConsoleMessage.text(message) =~ "stale edition" end
)
```

`Event.console()` resolves with a `Playwright.ConsoleMessage` and
`Event.page_error()` with the Playwright error of an uncaught exception
(`name`, `stack` and `Exception.message/1`). `Event.worker()` resolves with a
`Playwright.Worker` and `Event.web_socket()` with a `Playwright.WebSocket`.

`Event.dom_content_loaded()` and `Event.load()` resolve with the `Fluffy.Page` when that
page's document reaches those states, and `Event.crash()` when it crashes. A crash fails
the page's other waits, except `Event.close()`. `Event.frame_attached()` and `Event.frame_detached()` resolve
with a `Playwright.Frame`, like `Event.frame_navigated()`.

## Routing requests

To test the potions list without its API, register a route before visiting.
It intercepts matching requests across the browser context, including popups.
Answer each `Playwright.Route` once:

```elixir
alias Playwright.Route

session
|> route("/api/potions", fn route -> Route.fulfill!(route, json: [%{name: "Felix Felicis"}]) end)
|> route(~r{/api/owls$}, fn route -> Route.abort!(route) end)
|> visit("/potions")
|> assert_has(by_text("Felix Felicis"))
```

`url` is what Playwright's `route` takes: a glob string (resolved against
`base_url:`), a regular expression, or a predicate over the URL as a `%URI{}`. A handler
taking two arguments also gets the `Playwright.Request`.

Answers are `Playwright.Route.fulfill!/2` (status, headers, `body:`, `json:`,
`path:`, `response:` from `Playwright.Route.fetch!/2`), `continue!/2` (with
optional overrides), `abort!/2` and `fallback!/2`.
When several routes match, the last registered wins; `fallback` hands the
request to the route registered before it, and finally to the server.
`times:` limits how many requests a route handles, and `Fluffy.Playwright.unroute/3` removes a route
(for a given handler or all of them for that `url`). As in Playwright, it does not
wait for handlers already running: removing the last route lets their requests go on
to the server, so a late answer fails the test. `Fluffy.Playwright.unroute_all/2`
takes Playwright's `behavior:` to wait for them (`:wait`) or ignore their failures
(`:ignore_errors`).
Routing a document request, such as a `visit` or a link, works like any other:
the page loads the fulfilled document and Fluffy keeps tracking it.

As in Playwright, each handler runs in a process of its own, since the test
process is blocked in the action that caused the request. That process has the
process that called `Fluffy.Playwright.route/4` in `$callers`. Don't block in a
route handler (`receive`, `Process.sleep`, `GenServer` calls, database or Phoenix
work); hand off to a `Task` and fulfil from it. The `Task` inherits `$callers`, so
the Ecto sandbox works there:

```elixir
route(session, "**/owl-post/**", fn route ->
  Task.start(fn -> Route.fulfill!(route, json: Owlery.letters_for("Harry")) end)
end)
```

Register routes from the test, or from a process with the test in `$callers`. As in Playwright, a handler that
raises fails the test and leaves its request pending. A route lasts until `unroute/3`,
`unroute_all/2` or the session's end.

A handler may return without answering and leave the route to another process. To
hold a request while the test observes the page, send the route to the test
process and answer it there:

```elixir
test = self()
route(session, "/api/prophet", &send(test, {:held, &1}))

session
|> visit("/prophet")
|> assert_has(by_text("Loading"))

assert_receive {:held, route}
Route.fulfill!(route, json: %{title: "Evening Edition"})
assert_has(session, by_text("Evening Edition"))
```

As in Playwright, a request never answered hangs until the action waiting for it
times out.

## File choosers

Locate a file input directly when possible, including hidden inputs. For a button
whose JavaScript opens a chooser, register first and pass the returned value directly:

```elixir
pending = wait_for(session, Event.file_chooser())
click(session, button("Choose portrait"))
chooser = await(pending)
refute FileChooser.multiple?(chooser)
set_input_files(session, chooser, "test/support/fixtures/portrait.png")
```

The chooser identifies its source page. Setting files preserves the current-page
selection, even after switching elsewhere. This sets files programmatically; it
does not operate the OS picker. Choosers require Playwright.

## Cookies and storage

`Fluffy.add_cookies/2`, `Fluffy.cookies/2` and `Fluffy.clear_cookies/2` work on both
backends, on the session's whole browser context (see [Cookies](capabilities.md#cookies)).

`Fluffy.Playwright.storage_state/2` returns a state map with atom keys
(`:cookies`, `:origins`) and optionally writes JSON with `path:`. Include IndexedDB with `indexed_db: true`. Reuse the result
with `start_session(:playwright, browser_context: [storage_state: state])`.
