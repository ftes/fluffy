# Assertions

The snippets assume the imports from [Your first test](usage.md#your-first-test) and an initialized `session`.

Place `use Fluffy.Assert` after `use Playwright.Test` (or the case template that has it). It
imports the constructors and takes over only the conflicting `assert/2` and `refute/2`
imports. Ordinary ExUnit assertions, pattern bindings, custom messages, and other helpers
remain available, and each `assert` and `refute` is a step of the test's trace, as with
`use Playwright.Test` alone, unless it has `assert_steps: false`.

```elixir
use ExUnit.Case, async: true
use Playwright.Test
use Fluffy.Assert

import Fluffy
import Fluffy.Locator

test "registers a creature" do
  start_session(:phoenix)
  |> visit("/creatures/new")
  |> fill(by_label("Name"), "Basilisk")
  |> click(by_role(:button, name: "Register"))
  |> assert_has(by_text("Creature registered"))
  |> refute_has(by_text("Saving…"))
  |> refute(page_title("Error"))
  |> assert(page_url("/creatures/basilisk"))

  assert {:ok, name} = {:ok, "Basilisk"}
  assert name == "Basilisk", "ordinary ExUnit assertions still work"
end
```

`assert_has(locator)` is shorthand for `assert(visible(locator))`, and `refute_has(locator)`
for `refute(visible(locator))`. Use `assert` and `refute` for every other assertion. Options
such as `timeout:` go in the shorthand's options argument:

```elixir
session
|> assert_has(by_text("Creature registered"))
|> refute_has(by_text("Saving…"), timeout: 1_000)
```

See [Shared test case](usage.md#shared-test-case) to centralize these imports
and the session setup.

See `Fluffy.Assert` for all assertion constructors, their options, and which ones
require Playwright. For `assert_event`, see [Advanced events and pages](advanced-events.md).

## Options and negation

Options can go on the constructor or execution call. Execution options take
precedence, and both forms return the updated session:

```elixir
session
|> assert(page_title("Creatures", timeout: 1_000))
|> refute(page_title("Error"), timeout: 1_000)
```

`refute(session, expectation)` executes the negated expectation and preserves
driver errors. Retrying drivers wait until the negative condition holds; they do
not require it to hold for the entire timeout.
Event values use ordinary ExUnit assertions; event waiting is documented in
[Advanced events and pages](advanced-events.md).

Refuting visibility accepts an absent or invisible element. See
[Visibility and DOM presence](#visibility-and-dom-presence) for absence
checks, hidden elements, and the structural versus rendered visibility rules.

## Text, attributes, and state

`Fluffy.Assert` asserts text, attributes, classes, ids, and states the same way
on every driver:

```elixir
session
|> assert(text(by_role(:heading), "Creature saved"))
|> assert(contain_text(by_role(:alert), ~r/\d+ spells/))
|> assert(text(by_css("li"), ["Fluffy", "Norbert"]))
|> assert(attribute(by_role(:link, name: "Docs"), "href", "/docs"))
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

The PhoenixTest-style facade's `assert_has` and `refute_has` check visibility, and
their `count:` and `at:` count visible matches only; [Locators](locators.md#locators)
covers strictness. Field predicates (`value:`, `checked:`, `selected:`) without `at:`
add no visibility requirement, so they check hidden inputs too, and `selected:` on a select
checks its selected option. For DOM presence, including hidden inputs or script
elements, use a native count on the same session:
`assert(session, count(by_css("script[nonce]"), 1))`.

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

Like Playwright, Fluffy has no page status assertion. On Playwright, assert on the
navigation's response instead:

```elixir
session
|> assert_event(
  Fluffy.Event.response(&String.ends_with?(Playwright.Response.url(&1), "/potions")),
  &click(&1, by_role(:link, name: "Potions")),
  fn response -> assert Playwright.Response.status(response) == 200 end
)
```

## Polling and retrying blocks

Fluffy's assertions retry on their own, so prefer them. For what isn't one locator or page
assertion, such as a computed value or app state, use Playwright's
[`expect.poll` and `toPass`](https://playwright.dev/docs/test-assertions#expectpoll). In a
pipeline, `poll` and `pass` run
`Playwright.Expect.poll!/3` and `Playwright.Expect.to_pass!/2` with the session, on every driver.
`poll` calls its function again until the assertion passes on the value it returns; as upstream,
the assertion raises until the value is right, and a function that raises fails at once, so
return a value and leave the check to the assertion. Compare explicitly, as in
`&assert(&1 == "playing")`: JavaScript `null` (`:null`), `NaN` (`:nan`), `0` and `""` are truthy in
Elixir, so `&assert(&1)` passes on them, as a JavaScript condition would not. For a condition on
the page alone, `Fluffy.Playwright.wait_for_function/3` keeps JavaScript's truthiness. `pass`
retries whatever its block raises.
Both return the session (`pass` the one its passing attempt returned, if any) and fail like
other assertions, with the last error in the message. `refute(pass(fun))`
runs `Playwright.Expect.not_to_pass!/2`: it retries until the block
raises and fails at the timeout while it keeps passing. `poll` can't be refuted: refute in its
assertion.

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
  |> click(by_role(:button, name: "Check the owlery"), timeout: 1_000)
  |> assert_has(by_text("A letter for Harry"), timeout: :once)
end))
```

Outside a pipeline, call `Playwright.Expect.poll!/3` and `Playwright.Expect.to_pass!/2` with
Elixir callbacks directly. They fail with `Playwright.ExpectError`, and `to_pass!` returns the
passing attempt's value; `Playwright.Expect.poll/3` and `Playwright.Expect.to_pass/2` return
`:ok` or `{:ok, value}` and `{:error, error}` instead of raising.

```elixir
Playwright.Expect.poll!(fn -> Owlery.letters_for("Harry") end, &assert(length(&1) == 1))
```

`poll` retries for Playwright's expect timeout (5 s by default, `config :playwright, :test, expect:`) and
`pass` until the test's timeout, unless given a `timeout:`. Each attempt runs to the end: a
Fluffy assertion or action in the callback waits for its own timeout before `pass` tries
again, and an attempt still running at `pass`'s deadline isn't cut short, unlike in
Playwright's JavaScript. So give the calls inside short timeouts: `timeout: :once` makes an
assertion check once and leaves the retrying to `pass`; actions need a short positive one,
as Playwright actions reject `:once`. Outside a retried block, use `:once` only to check that
something already holds, such as no partial list right after a reconnect: a single check of a
page that is still updating is flaky, so keep the default there.

A LiveView or browser page updates between attempts; a Static page doesn't, as it is a
response. On Static, poll app state, or `reload` in the callback to fetch the page again.
