# Assertions

The snippets assume the imports from [Your first test](usage.md#your-first-test) and an initialized `session`.

Fluffy's native locator API offers two vocabularies for the same assertions. The guides use
`assert` and `refute`; choose `expect` if you prefer Playwright-style names.
Both construct the same expectation values and preserve driver behavior,
retries, timeout options, diagnostics, and the returned session.

## ExUnit style

Place `use Fluffy.Assert` after `use ExUnit.Case` or your application's case module. It
imports the constructors and replaces only ExUnit's conflicting
`ExUnit.Assertions.assert/2` and `ExUnit.Assertions.refute/2` imports. Ordinary ExUnit
assertions, pattern bindings, custom messages, and other helpers remain available.

```elixir
use ExUnit.Case, async: true
use Fluffy.Assert

import Fluffy
import Fluffy.Locator

test "registers a creature" do
  start_session(:phoenix)
  |> visit("/creatures/new")
  |> fill(by_label("Name"), "Basilisk")
  |> click(by_role(:button, name: "Register"))
  |> assert(visible(by_text("Creature registered")))
  |> refute(page_title("Error"))
  |> assert(page_url("/creatures/basilisk"))

  assert {:ok, name} = {:ok, "Basilisk"}
  assert name == "Basilisk", "ordinary ExUnit assertions still work"
end
```

For visibility checks, `assert_has(session, locator, options \\ [])` and
`refute_has(session, locator, options \\ [])` are shorthand for
`assert(session, visible(locator), options)` and its refutation:

```elixir
session
|> assert_has(by_text("Creature registered"))
|> refute_has(by_text("Saving…"), timeout: 1_000)
```

See [Shared test case](usage.md#shared-test-case) to centralize these imports
and lifecycle setup.

## Expect style

Use `import Fluffy.Expect` in place of `use Fluffy.Assert`. Actions and locators
keep their names; assertion constructors use `to_be_*` and `to_have_*`.

```elixir
use ExUnit.Case, async: true

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
| `assert(checked(locator))` | `expect(to_be_checked(locator))` |
| `assert(enabled(locator))` | `expect(to_be_enabled(locator))` |
| `assert(count(locator, 3))` | `expect(to_have_count(locator, 3))` |
| `assert(value(locator, "Basilisk"))` | `expect(to_have_value(locator, "Basilisk"))` |
| `assert(text(locator, "Basilisk"))` | `expect(to_have_text(locator, "Basilisk"))` |
| `assert(attribute(locator, "href", "/creatures"))` | `expect(to_have_attribute(locator, "href", "/creatures"))` |
| `assert(hidden(locator))` | `expect(to_be_hidden(locator))` |
| `assert(page_url("/creatures"))` | `expect(page_to_have_url("/creatures"))` |
| `assert(page_title("Creatures"))` | `expect(page_to_have_title("Creatures"))` |

Use `Fluffy.Assert.assert_event/4` or the equivalent `Fluffy.Expect.expect_event/4` for
events. The optional assertion receives an ordinary event value; use ExUnit assertions
on its fields. See [Events and pages](advanced-events.md).

The same naming pattern applies to the remaining constructors. See the
`Fluffy.Assert` and `Fluffy.Expect` references for their complete APIs.

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
[Events and pages](advanced-events.md).

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
`ArgumentError`, and a `PlaywrightEx.RegExp` takes JavaScript-only syntax.
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

Without `count:` or a field predicate, the PhoenixTest-style facade's `assert_has`
and `refute_has` check visibility; [Locators](locators.md#locators) covers strictness.
Counts and field predicates (`value:`, `checked:`, `selected:`) add no visibility
requirement. Use `assert_has(selector, count: 1)` for DOM presence, including
hidden inputs or script elements, and `selected:` on a select to check its
selected option.

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
  Fluffy.Event.response(&String.ends_with?(PlaywrightEx.Response.url(&1), "/potions")),
  &click(&1, by_role(:link, name: "Potions")),
  fn response -> assert PlaywrightEx.Response.status(response) == 200 end
)
```
