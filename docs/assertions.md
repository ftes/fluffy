# Assertions

The snippets assume the imports from [Your first test](usage.md#your-first-test) and an initialized `session`.

Fluffy's native locator API offers two vocabularies for the same assertions. The guides use
`assert` and `refute`; choose `expect` if you prefer Playwright-style names.
Both construct the same expectation values and preserve driver behavior,
retries, timeout options, diagnostics, and the returned session.

## ExUnit style

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

## Expect style

Use `import Fluffy.Expect` in place of `use Fluffy.Assert`. Actions and locators
keep their names; assertion constructors use `to_be_*` and `to_have_*`.

```elixir
use ExUnit.Case, async: true
use Playwright.Test

import Fluffy
import Fluffy.Expect
import Fluffy.Locator

test "registers a creature" do
  start_session(:phoenix)
  |> visit("/creatures/new")
  |> fill(by_label("Name"), "Basilisk")
  |> click(by_role(:button, name: "Register"))
  |> expect(to_be_visible(by_text("Creature registered")))
  |> expect(not_(page_to_have_title("Error")))
  |> expect(page_to_have_url("/creatures/basilisk"))
end
```

## Naming comparison

The following calls are pipeline steps, with the session supplied by `|>`.
Locator constructors take a locator; page constructors target the active page.

| ExUnit style | Expect style |
| --- | --- |
| `assert(visible(locator))` | `expect(to_be_visible(locator))` |
| `refute(visible(locator))` | `expect(not_(to_be_visible(locator)))` |
| `assert(hidden(locator))` | `expect(to_be_hidden(locator))` |
| `assert(attached(locator))` | `expect(to_be_attached(locator))` |
| `assert(checked(locator))` | `expect(to_be_checked(locator))` |
| `assert(enabled(locator))` | `expect(to_be_enabled(locator))` |
| `assert(disabled(locator))` | `expect(to_be_disabled(locator))` |
| `assert(editable(locator))` | `expect(to_be_editable(locator))` |
| `assert(empty(locator))` | `expect(to_be_empty(locator))` |
| `assert(focused(locator))` | `expect(to_be_focused(locator))` |
| `assert(in_viewport(locator))` | `expect(to_be_in_viewport(locator))` |
| `assert(count(locator, 3))` | `expect(to_have_count(locator, 3))` |
| `assert(value(locator, "Basilisk"))` | `expect(to_have_value(locator, "Basilisk"))` |
| `assert(values(locator, ["owl", "toad"]))` | `expect(to_have_values(locator, ["owl", "toad"]))` |
| `assert(text(locator, "Basilisk"))` | `expect(to_have_text(locator, "Basilisk"))` |
| `assert(contain_text(locator, "Basil"))` | `expect(to_contain_text(locator, "Basil"))` |
| `assert(attribute(locator, "href", "/creatures"))` | `expect(to_have_attribute(locator, "href", "/creatures"))` |
| `assert(class(locator, "card selected"))` | `expect(to_have_class(locator, "card selected"))` |
| `assert(contain_class(locator, "selected"))` | `expect(to_contain_class(locator, "selected"))` |
| `assert(id(locator, "name"))` | `expect(to_have_id(locator, "name"))` |
| `assert(css(locator, "display", "flex"))` | `expect(to_have_css(locator, "display", "flex"))` |
| `assert(js_property(locator, "checked", true))` | `expect(to_have_js_property(locator, "checked", true))` |
| `assert(role(locator, :button))` | `expect(to_have_role(locator, :button))` |
| `assert(accessible_name(locator, "Register"))` | `expect(to_have_accessible_name(locator, "Register"))` |
| `assert(accessible_description(locator, "Your full name"))` | `expect(to_have_accessible_description(locator, "Your full name"))` |
| `assert(accessible_error_message(locator, "Too short"))` | `expect(to_have_accessible_error_message(locator, "Too short"))` |
| `assert(match_aria_snapshot(locator, "- button"))` | `expect(to_match_aria_snapshot(locator, "- button"))` |
| `assert(match_screenshot(locator, name: "card.png"))` | `expect(to_have_screenshot(locator, name: "card.png"))` |
| `assert(page_url("/creatures"))` | `expect(page_to_have_url("/creatures"))` |
| `assert(page_title("Creatures"))` | `expect(page_to_have_title("Creatures"))` |
| `assert(page_match_aria_snapshot("- heading"))` | `expect(page_to_match_aria_snapshot("- heading"))` |
| `assert(page_match_screenshot(name: "creatures.png"))` | `expect(page_to_have_screenshot(name: "creatures.png"))` |
| `assert(page_opener(page))` | `expect(page_to_have_opener(page))` |
| `assert(pass(fn session -> ... end))` | `expect(to_pass(fn session -> ... end))` |
| `assert(poll(fn session -> ... end, &assert(&1 == 1)))` | `expect(poll(fn session -> ... end, &assert(&1 == 1)))` |

Use `Fluffy.Assert.assert_event/4` or the equivalent `Fluffy.Expect.expect_event/4` for
events. The optional assertion receives an ordinary event value; use ExUnit assertions
on its fields. See [Advanced events and pages](advanced-events.md).

See the `Fluffy.Assert` and `Fluffy.Expect` references for their options and which
ones require Playwright.

## Options and negation

Options can go on the constructor or execution call. Execution options take
precedence, and both forms return the updated session:

```elixir
session
|> assert(visible(by_text("Creature registered"), timeout: 1_000))
|> refute(visible(by_text("Saving…")), timeout: 1_000)
```

`refute(session, expectation)` executes the negated expectation, just like
`expect(session, not_(expectation))`. It preserves driver errors rather than
turning them into successful refutations. Retrying drivers wait until the
negative condition holds; they do not require it to hold for the entire timeout.
Event values use ordinary ExUnit assertions; event waiting is documented in
[Advanced events and pages](advanced-events.md).

Refuting visibility accepts an absent or invisible element. See
[Visibility and DOM presence](#visibility-and-dom-presence) for absence
checks, hidden elements, and the structural versus rendered visibility rules.
Choosing a vocabulary does not change those driver boundaries.

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

`hidden` passes when nothing matches, as does `refute(visible(locator))`.
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
`<style>`, `<template>` or `<datalist>`, and fallback content such as a
`<video>`'s children. `aria-hidden="true"` does not count, as in Playwright: it
only keeps an element out of `by_role`.

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
see [Boundaries](capabilities.md#boundaries) for `<details>`, `<dialog>`,
`popover` and the options of a closed `<select>`.

Choose the assertion that expresses the intended behavior:

```elixir
# Require a visible element.
session |> assert(visible(by_css("#notice")))

# Allow the element to be absent or invisible.
session |> refute(visible(by_css("#notice")))

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
pipeline, `poll` and `pass` (`poll` and `to_pass` with `import Fluffy.Expect`) run
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
(`not_(to_pass(fun))`) runs `Playwright.Expect.not_to_pass!/2`: it retries until the block
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
  |> assert_has(by_text("A letter for Harry"), timeout: 0)
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
Playwright's JavaScript. So give the calls inside short timeouts: `timeout: 0` makes an
assertion check once and leaves the retrying to `pass`; actions need a short positive one,
as Playwright actions reject `0`.

A LiveView or browser page updates between attempts; a Static page doesn't, as it is a
response. On Static, poll app state, or `reload` in the callback to fetch the page again.
