# Advanced events and pages

The examples use the standard test-module convention from the usage guide:
`import Fluffy.Expect`, plus aliases for `Fluffy.Event` and `Fluffy.Page`.

Every `wait_for(Event.*(...), action)` call is listener-before-action and
pipeable. The action callback must return its updated session. Captured keys
are immutable and results are non-consuming. Fluffy installs the listener
before it invokes the action callback.

## Downloads

```elixir
session
|> wait_for(Event.download(:report), fn session ->
  click(session, by_role(:button, name: "Download potion ledger"))
end)
|> expect(to_have_download_suggested_filename(:report, "potions.csv"))
|> expect(to_have_download_content_type(:report, "text/csv"))
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
|> expect(Page.to_have_opener(:main))
|> expect(Page.to_have_url(path: "/chambers/secrets"))
|> expect(by_role(:heading, name: "Secret chamber") |> to_be_visible())
|> close_page()
|> expect(by_text("Creature index") |> to_be_visible())
```

Multiple pages and tabs require Playwright. Phoenix follows links and submits
forms in its current page, ignoring `target` and `formtarget`, including
`_blank`. Popup capture, page switching, and closing pages raise a capability
error in Phoenix. Multiple isolated sessions remain supported by both backends.
All pages inside one Playwright session share cookies/storage; independent
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
|> expect(to_have_navigation_url(:forbidden_forest, forbidden_forest_url))
|> expect(to_have_navigation_status(:forbidden_forest, 200))
```

## Dialogs

Dialogs are atomic browser-only events. The decision is installed before the
action so an unhandled modal cannot deadlock the click:

```elixir
session
|> wait_for(Event.dialog(:release_basilisk, accept: true), fn session ->
  click(session, by_role(:button, name: "Release basilisk"))
end)
|> expect(to_have_dialog_type(:release_basilisk, :confirm))
|> expect(to_have_dialog_message(:release_basilisk, "Release the basilisk?"))
|> expect(to_have_dialog_action(:release_basilisk, :accept))
```

Use `:dismiss`, `{:accept, "prompt text"}`, or a decision function receiving
the unhandled `%Fluffy.Dialog{}`.

## Requests and responses

```elixir
session
|> wait_for(Event.response(:potions, ~r{/api/potions}), fn session ->
  click(session, by_role(:button, name: "Refresh potions"))
end)
|> expect(to_have_response_status(:potions, 200))
|> expect(to_have_response_resource_type(:potions, "fetch"))
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
  bytes: png_bytes,
  content_type: "image/png"
})
```

`file_chooser(session, :portrait)` returns the opaque
`%Fluffy.FileChooser{}`; `Fluffy.FileChooser.multiple?/1` exposes whether
it accepts multiple files. The chooser result is non-consuming and lives with
the session, but it belongs to the page that opened it. Scripted chooser events
are Playwright-only because Static and LiveView do not execute application
JavaScript. This API sets files programmatically; it does not operate the OS
picker UI.

## Failure artifacts

Setting `FLUFFY_ARTIFACT_DIR` through the Playwright `artifact_dir`
configuration is recommended. It captures full-page PNG, HTML, and formatted
exception text when a public Playwright driver operation fails; configure CI
to upload that directory on failure. A capture error never replaces the actual
test failure. Artifacts are evidence for debugging, not conformance input.
