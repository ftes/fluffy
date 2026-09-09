# Advanced events and pages

The examples assume the [test setup](usage.md#your-first-test), an initialized
`session`, and application routes and controls matching each scenario. Use
these imports and aliases after your ExUnit case module:

```elixir
use Fluffy.Assert

import Fluffy
import Fluffy.Locator

alias Fluffy.{Event, FileChooser, Page}
```

`use Fluffy.Assert` imports the assertion vocabulary. Page and captured-result
constructors use target prefixes, such as `page_url` and `response_status`.

`wait_for(Event.*(...), action)` installs the listener before running the
action. Return the updated session from the callback. Captured results can be
read repeatedly through their keys.

## Downloads

```elixir
session
|> wait_for(Event.download(:report), fn session ->
  click(session, by_role(:button, name: "Download potion ledger"))
end)
|> assert(download_suggested_filename(:report, "potions.csv"))
|> assert(download_content_type(:report, "text/csv"))
```

`download(session, :report)` returns `%Fluffy.Download{}` with `filename`,
`content_type`, `bytes`, and `url`. Override the default retained-byte limit
with `max_bytes:` on `Event.download/2` or `wait_for/4`.

## New pages and tabs (Playwright only)

```elixir
session
|> wait_for(Event.popup(:secret_chamber), fn session ->
  click(session, by_role(:button, name: "Open chamber in new tab"))
end)
|> switch_page(:secret_chamber)
|> assert(page_opener(:main))
|> assert(page_url(path: "/chambers/secrets"))
|> assert(visible(by_role(:heading, name: "Chamber of Secrets")))
|> close_page()
|> assert(visible(by_text("Creature index")))
```

Multiple pages and tabs require Playwright. Phoenix follows links and submits
forms in its current page, ignoring `target` and `formtarget`, including
`_blank`. Popup capture, page switching, and closing pages raise a capability
error in Phoenix. Multiple isolated sessions remain supported by both backends.
All pages inside one Playwright session share cookies and storage; independent
sessions do not.

`page(session, :secret_chamber)` returns the captured opaque `Fluffy.Page`; use
`Page.name/1`, `Page.url/1`, `Page.status/1`, `Page.opener/1`, and
`Page.revision/1` to inspect its metadata without switching.

## Navigation

```elixir
session
|> wait_for(Event.navigation(:forbidden_forest), fn session ->
  click(session, by_role(:link, name: "Follow the spiders"))
end)
|> assert(navigation_url(:forbidden_forest, path: "/forest"))
|> assert(navigation_status(:forbidden_forest, 200))
```

Captured download, navigation, request, and response URL assertions
accept exact strings, regexes, or structured path, query, and fragment matchers.
This also applies to `navigation_from_url/3`. Strings are compared as
captured, without resolving relative URLs. Structured matching follows the
[same rules as page URL assertions](usage.md#page-assertions): query matching is
exact by default; use `query_mode: :subset` to allow additional parameter names.

```elixir
session
|> assert(
  navigation_url(:forbidden_forest,
    path: "/forest",
    query: %{"guide" => "spiders"},
    query_mode: :subset
  )
)
```

These assertions inspect the retained event result; they do not wait for the
active page to change. `wait_for/3` handles waiting for the event.

## Dialogs

Dialogs are atomic browser-only events. The decision is installed before the
action so an unhandled modal cannot deadlock the click:

```elixir
session
|> wait_for(Event.dialog(:delete_recipe, decision: :accept), fn session ->
  click(session, by_role(:button, name: "Delete recipe"))
end)
|> assert(dialog_type(:delete_recipe, :confirm))
|> assert(dialog_message(:delete_recipe, "Delete this recipe?"))
|> assert(dialog_action(:delete_recipe, :accept))
```

Set `decision:` to `:accept`, `:dismiss`, `{:accept, "prompt text"}`, or a
function receiving the unhandled `%Fluffy.Dialog{}`.

## Requests and responses

```elixir
session
|> wait_for(Event.response(:potions, ~r{/api/potions}), fn session ->
  click(session, by_role(:button, name: "Refresh potions"))
end)
|> assert(response_status(:potions, 200))
|> assert(response_resource_type(:potions, "fetch"))
```

Matchers can be an exact URL, regex, or normalized-event predicate. These are
browser-wide subresource streams and therefore Playwright-only. The event
contains method, URL, headers, resource type, post data, status fields, and the
known page name.

## File choosers

Directly locating the file input is preferred, even when it is hidden.
Applications sometimes expose only a button whose JavaScript opens the input's
native chooser. Capture that browser event before clicking, then pass its key
to the same file-selection action:

```elixir
session
|> wait_for(Event.file_chooser(:portrait), fn session ->
  click(session, by_role(:button, name: "Choose creature portrait"))
end)
|> set_input_files(:portrait, %Fluffy.FilePayload{
  name: "fluffy.png",
  bytes: File.read!("test/support/fixtures/fluffy.png"),
  content_type: "image/png"
})
```

`file_chooser(session, :portrait)` returns the opaque
`%Fluffy.FileChooser{}`; `FileChooser.multiple?/1` exposes whether
it accepts multiple files. The chooser result is non-consuming and lives with
the session, but it belongs to the page that opened it. Scripted chooser events
are Playwright-only because Static and LiveView do not execute application
JavaScript. This API sets files programmatically; it does not operate the OS
picker UI.

See [Browser diagnostics](usage.md#browser-diagnostics) for traces, screenshots,
and failure artifacts.
