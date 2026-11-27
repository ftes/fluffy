# Assertions

The snippets assume the imports from [Your first test](usage.md#your-first-test) and an initialized `session`.

Use `assert_has` and `refute_has` for visibility. For other conditions, pipe the
session into `assert` or `refute` with a constructor from `Fluffy.Assert`:

```elixir
session
|> click(button("Register"))
|> assert_has(by_text("Creature registered"))
|> refute_has(by_text("Saving…"))
|> assert(page_path("/creatures/basilisk"))
```

Ordinary ExUnit assertions still work, including pattern bindings and custom messages.
Assertions appear in the test trace unless `assert_steps: false` is set.

## Options and negation

Pass options on the assertion, for example `assert_has(by_text("Ready"), timeout: 1_000)`.
Execution options override options on the constructor. `refute` waits until the negative
condition holds; it doesn't require that condition to hold for the whole timeout or
turn a driver error into success. For events, use [assert_event](advanced-events.md#pipeline-expectations).

## Text, attributes, and state

`Fluffy.Assert` asserts text, attributes, classes, ids, and states the same way
on every driver:

```elixir
session
|> assert(text(by_role(:heading), "Creature saved"))
|> assert(contain_text(by_role(:alert), ~r/\d+ spells/))
|> assert(text(by_css("li"), ["Fluffy", "Norbert"]))
|> assert(attribute(link("Docs"), "href", "/docs"))
|> assert(class(by_css("#card"), "card selected"))
|> assert(contain_class(by_css("#card"), "selected"))
|> assert(id(by_label("Name"), "name"))
|> assert(attached(by_css("#card")))
|> assert(hidden(by_text("Saving")))
|> assert(empty(by_label("Notes")))
```

A string compares normalized whitespace in the text; a regular expression sees
it as is. LiveView text can differ in whitespace-only nodes between elements:
`<b>a</b> <i>b</i>` reads "ab" there. A regular expression is a JavaScript
`RegExp` on every driver, as in [Locators](locators.md): PCRE-only syntax raises
`ArgumentError`, and a `Playwright.RegExp` takes JavaScript-only syntax.
`ignore_case:` takes precedence over a regular expression's own flag.
A list checks each matched element in order, while any other form requires
exactly one match. `use_inner_text: true` reads rendered text and requires
Playwright, so `text` and `contain_text` raise
`Fluffy.CapabilityError` on Static and LiveView when given it.

`value` and `values` accept strings and regular expressions (`~r/…/` or
`Playwright.RegExp`) and compare the raw control values. On a multi-select,
`values` compares every selected option in document order, one per list entry.
For example, `assert(session, values(by_label("Potions"), ["polyjuice", ~r/^felix-/]))`.

`hidden` passes when nothing matches, as does `refute_has(locator)`.
Negating `text`, `contain_text`, `attribute`, `class`,
`contain_class`, `id`, or `empty` still fails when nothing matches.

Known limits: on Static and LiveView, `empty` can differ from a browser for
a checkbox, radio, range or color input and a script-only element, and attribute
names match exactly; on Playwright, `submit` can return early when a submit handler
that does not cancel changes the URL in the document (`pushState`, `replaceState`,
`location.hash`), so use a retrying `assert` afterwards.

## Visibility and DOM presence

Even the `:phoenix` backend checks **structural visibility**, rather than just
DOM presence. Its Static and LiveView drivers treat what markup alone keeps from
rendering as invisible: a `hidden` attribute on the element or an ancestor, an
`<input type="hidden">`, elements a browser never displays such as `<script>`,
`<style>`, `<template>` or `<datalist>`, fallback content such as a
`<video>`'s children, and the options of a closed dropdown `<select>`, which have no box
in a browser ([Selects and options](actions.md#selects-and-options)).
`aria-hidden="true"` does not count, as in Playwright: it only keeps an element out of
`by_role`.

Phoenix does not compute CSS or browser layout: a CSS class or inline
`display: none` alone does not make an element structurally invisible. Use
`:playwright` to test rendered visibility. Open state is not modeled either:
see [Boundaries](capabilities.md#boundaries) for `<details>`, `<dialog>` and
`popover`.

Choose the assertion that expresses the intended behavior:

```elixir
# Require a visible element.
session |> assert_has(by_css("#notice"))

# Allow the element to be absent or invisible.
session |> refute_has(by_css("#notice"))

# Require DOM absence, including hidden elements.
session |> assert(count(by_css("#notice"), 0))
```

To require an element to remain in the DOM but be invisible, assert
`count(by_css("#notice"), 1)` before refuting its visibility. Use a CSS locator
for these presence checks; role locators can exclude structurally hidden
elements before the assertion runs.

## Page assertions

Page assertion constructors use a `page_` prefix and target
the active page:

```elixir
session
|> assert(page_title("Chamber of Secrets"))
|> assert(page_title(~r/^Chamber/))
|> refute(page_title("Chamber sealed"))
```

Title assertions normalize whitespace. LiveView and Playwright retry until
the title matches; Static checks immediately. LiveView also observes later
`@page_title` updates, including `live_title` prefixes and suffixes.

URL assertions use the same `page_` prefix and take what Playwright's `toHaveURL`
takes. A string is resolved against the session base URL and must equal the
complete URL, query and fragment included. A regular expression matches the URL,
and a function gets the URL as a `%URI{}`, as Playwright passes a `URL`:

```elixir
session
|> assert(page_url("/potions"))
|> assert(page_url(~r{/potions\?state=brewing}))
|> assert(page_url(&(URI.decode_query(&1.query || "")["state"] == "brewing")))
```

Predicates work with every driver and with negated assertions. Keep them quick
and nonblocking.

With `use Fluffy.Assert`, use `page_path` to match only the URI path, ignoring the
origin, fragment, and (by default) query:

```elixir
session
|> assert(page_path("/potions"))
|> assert(page_path("/potions", params: %{state: "brewing", page: 2}))
|> refute(page_path("/potions", params: &Map.has_key?(&1, "finished")))
```

A `params:` map matches a subset of the decoded query in any order. Flat atom or
string keys and scalar values are converted with `to_string/1`. A predicate gets
the decoded map with string keys and values (`%{}` for an absent or empty query).
Decoding uses `URI.decode_query/1`, so the last value for a repeated key wins. Use
`page_url` to match the full URL, inspect the raw query, or check repeated pairs.
`page_path` uses the same timeout and negation as `page_url`, testing the path and
parameters together on each attempt.

Like Playwright, Fluffy has no page status assertion. On Playwright, assert on the
navigation's response instead:

```elixir
session
|> assert_event(
  Fluffy.Event.response(&String.ends_with?(Playwright.Response.url(&1), "/potions")),
  &click(&1, link("Potions")),
  fn response -> assert Playwright.Response.status(response) == 200 end
)
```

## Polling and retrying blocks

Prefer a locator or page assertion for UI state. For anything else, choose what to retry:

- `assert(poll(read, check))` reads a value and retries when the check raises. If the
  read raises, the test fails immediately. Compare JavaScript values explicitly:
  `:null`, `:nan`, `0` and `""` are truthy in Elixir. Use `Fluffy.Playwright.wait_for_function/3`
  for a condition that should run in JavaScript.
- `assert(pass(fun))` retries the whole block when it raises. `refute(pass(fun))`
  retries until the block raises. To negate a poll, use `refute` inside its check.

```elixir
session
# Wait for app state, such as a job the click started.
|> assert(poll(fn _session -> Owlery.letters_for("Harry") end, &assert(length(&1) == 1),
  message: "an owl reaches Privet Drive",
  timeout: 10_000
))
# Retry a block until it passes.
|> assert(pass(fn session ->
  session
  |> click(button("Check the owlery"), timeout: 1_000)
  |> assert_has(by_text("A letter for Harry"), timeout: :once)
end))
```

`poll` uses Playwright's expect timeout (default 5 s); `pass` uses the test timeout.
Override either with `timeout:`. An attempt runs to completion, even past the deadline.
Inside `pass`, give actions a short positive timeout and assertions `timeout: :once`
so the block owns the retry. Outside a retry, keep the default for a page still updating.

A LiveView or browser page updates between attempts; a Static page doesn't, as it is a
response. On Static, poll app state, or `reload` in the callback to fetch the page again.
