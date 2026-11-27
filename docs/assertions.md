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
`assert_steps: false` disables ExUnit assertion steps in the trace; Playwright
still records its native matcher calls.

## Options and negation

Pass options on the assertion, for example `session |> assert_has(by_text("Ready"), timeout: 1_000)`.
Execution options override options on the constructor. On LiveView and Playwright,
`refute` waits until the negative condition holds; Static checks once. Refutation
doesn't require that condition to hold for the whole timeout or
turn a driver error into success. For events, use [assert_event](advanced-events.md#pipeline-expectations).

## Text, attributes, and state

To check the creature roster, assert on the list items themselves. A list of
expected texts checks every match in document order:

```elixir
roster = by_role(:list, "Creatures")

session
|> assert(text(by_role(roster, :listitem), ["Fluffy", "Norbert"]))
|> assert(attribute(link("Creature care"), "href", "/creatures/care"))
```

A single expected text requires exactly one element. Strings normalize whitespace;
a [regular expression](locators.md#locators) sees the raw text, unless the driver
has already lost whitespace-only nodes (on LiveView, `<b>a</b> <i>b</i>` reads
`"ab"`). `ignore_case:` overrides the regex flag. For rendered text, use
`use_inner_text: true` on Playwright.

`value` and `values` accept strings and regular expressions (`~r/…/` or
`Playwright.RegExp`) and compare the raw control values. On a multi-select,
`values` compares every selected option in document order, one per list entry.
For example, `assert(session, values(by_label("Potions"), ["polyjuice", ~r/^felix-/]))`.

`hidden` passes when nothing matches, as does `refute_has(locator)`.
Negating a single-target text, attribute, class, ID or empty check still fails
if the element is missing. A list assertion compares the matches as a collection:
if you refute a nonempty list of texts, an empty collection passes.

On Static and LiveView, attribute names match exactly. `empty` can differ from a
browser for checkbox, radio, range or color inputs and script-only elements.

## Visibility and DOM presence

After dismissing a notice, do you care that the user can't see it, or that
the app removed the element? Choose the assertion accordingly:

```elixir
# Require a visible element.
session |> assert_has(by_css("#notice"))

# Allow the element to be absent or invisible.
session |> refute_has(by_css("#notice"))

# Require DOM absence, including hidden elements.
session |> assert(count(by_css("#notice"), 0))
```

To require an element that is **both present and invisible**, use
`assert(session, count(by_css("#notice") |> filter(visible: false), 1))`.
Use CSS for presence checks: role locators can exclude hidden
elements, including those marked `aria-hidden="true"`. That attribute alone does
not hide the element visually.

Phoenix checks **structural visibility**: a `hidden` ancestor, a hidden input,
non-rendered elements such as `<script>`, media fallback content and
[closed dropdown options](actions.md#selects-and-options) are invisible. CSS alone
(`display: none`, for example) doesn't count. Use Playwright for rendered visibility
and [open or closed dialogs and details](capabilities.md#when-to-choose-playwright).

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
|> assert(page_url("/potions?state=brewing"))
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

- `session |> assert(poll(read, check))` reads a value and retries when the check raises. If the
  read raises, the test fails immediately. Compare JavaScript values explicitly:
  `:null`, `:nan`, `0` and `""` are truthy in Elixir. Use `Fluffy.Playwright.wait_for_function/3`
  for a condition that should run in JavaScript.
- `session |> assert(pass(fun))` retries the whole block when it raises. `session |> refute(pass(fun))`
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
