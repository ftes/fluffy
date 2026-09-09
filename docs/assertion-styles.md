# Assertion styles

Fluffy offers two imported vocabularies for the same assertions. The guides use
`assert` and `refute`; choose `expect` if you prefer Playwright-style names.
Both construct the same expectation values and preserve driver behavior,
retries, timeout options, diagnostics, and the returned session.

## ExUnit style

Place `use Fluffy.Assert` after `use ExUnit.Case` or your application's case
module. It imports the constructors and replaces only ExUnit's conflicting
`assert/2` and `refute/2` imports. Ordinary ExUnit assertions, pattern bindings,
custom messages, and other helpers remain available.

```elixir
use ExUnit.Case, async: true
use Fluffy.Assert

import Fluffy
import Fluffy.Locator

setup context do
  Fluffy.Test.setup(context)
end

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

setup context do
  Fluffy.Test.setup(context)
end

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
Locator constructors take a locator, page constructors target the active page,
and captured-result constructors take the capture key first.

| ExUnit style | Expect style |
| --- | --- |
| `assert(visible(locator))` | `expect(to_be_visible(locator))` |
| `refute(visible(locator))` | `expect(not_(to_be_visible(locator)))` |
| `assert(checked(locator))` | `expect(to_be_checked(locator))` |
| `assert(enabled(locator))` | `expect(to_be_enabled(locator))` |
| `assert(count(locator, 3))` | `expect(to_have_count(locator, 3))` |
| `assert(value(locator, "Basilisk"))` | `expect(to_have_value(locator, "Basilisk"))` |
| `assert(page_url("/creatures"))` | `expect(page_to_have_url("/creatures"))` |
| `assert(page_title("Creatures"))` | `expect(page_to_have_title("Creatures"))` |
| `assert(download_suggested_filename(:report, "report.csv"))` | `expect(download_to_have_suggested_filename(:report, "report.csv"))` |
| `assert(dialog_message(:confirmation, "Saved"))` | `expect(dialog_to_have_message(:confirmation, "Saved"))` |
| `assert(navigation_url(:destination, path: "/creatures"))` | `expect(navigation_to_have_url(:destination, path: "/creatures"))` |
| `assert(request_method(:save, "POST"))` | `expect(request_to_have_method(:save, "POST"))` |
| `assert(response_status(:save, 201))` | `expect(response_to_have_status(:save, 201))` |

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
Captured-result assertions inspect an already retained result immediately;
their timeout does not wait for a new event. Capture that event with `wait_for`.

Refuting visibility accepts an absent or invisible element. See
[Visibility and DOM presence](usage.md#visibility-and-dom-presence) for absence
checks, hidden elements, and the structural versus rendered visibility rules.
Choosing a vocabulary does not change those driver boundaries.
