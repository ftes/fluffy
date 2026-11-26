# Locators and frames

The snippets assume the imports from [Your first test](usage.md#your-first-test) and an initialized `session`.

## Locators

Prefer locators that describe the interface as a user experiences it:

1. Use a label for a form control.
2. Use a role and accessible name for an interactive element.
3. Use text for rendered content, with a visibility assertion when needed.
4. Use a test ID when user-facing names are ambiguous.
5. Use CSS for structure that has no user-facing identity.

```elixir
session
|> fill(by_label("Name"), "Basilisk")
|> click(by_role(:button, name: "Register"))
|> assert_has(by_text("Creature registered"))
```

Locators are values, so they can be scoped and reused:

```elixir
potions = by_css("#potions")
potion = potions |> by_role(:row, "Polyjuice Potion")

session
|> click(by_role(potion, :button, "Inspect"))
```

`by_role(:heading, "Potions", level: 2)` is the same as
`by_role(:heading, name: "Potions", level: 2)`. The positional name also works
when starting from another locator or a frame, and can be a regular expression.

Available constructors are `by_role`, `by_text`, `by_label`,
`by_placeholder`, `by_alt_text`, `by_title`, `by_test_id`, and `by_css`.
Text, role-name, and label matching default to normalized substring matching;
use `exact: true` for a complete match. Role names follow accessible-name
precedence: `aria-labelledby`, then `aria-label`, then native labels and
captions, then content for the roles Playwright names from content, then
`title`. Landmarks, lists, list items and dialogs are not named by their content.
`by_test_id` reads Playwright Test's `testIdAttribute` on every driver,
`config :playwright, :test, test_id_attribute: "data-owl"` (`data-testid` by default), or any
of a comma-separated list. It is one per suite, as in Playwright: each pooled browser gets it as
it starts.
Explicit ARIA roles override implicit roles. See `Fluffy.Locator.by_role/2` for the
implicit roles the Phoenix backend knows. Phoenix computes roles and names from
markup, so names ignore computed CSS and control values changed since rendering.
CSS must be valid browser CSS; escape special characters in IDs or use a
semantic/test-id locator.

Role state options, such as `by_role(:option, name: "Elder", selected: true)`,
`by_role(:button, pressed: true)` or `by_role(:heading, level: 2)`, work on every
driver. Static and LiveView read `checked:` and `selected:` from the controls' current
state, as `check` and `select_option` leave it, and the other states from markup;
`include_hidden:` uses their structural visibility. An input's `indeterminate`
property, which only JavaScript sets, is mixed on Playwright only; `aria-checked="mixed"`
is mixed on every driver. As in Playwright, a state option the role lacks, such as
`by_role(:link, pressed: true)`, raises when the locator resolves.

Role names, `has_text:` and `has_not_text:` also take a regular expression, as in
Playwright: the role locator tests it against the normalized accessible name, and
the text filters against the element's raw text, so `~r/^Pro$/` does not match
`<li> Pro </li>`. A regex is a JavaScript `RegExp` on every driver: an Elixir
`Regex` becomes one with `Playwright.RegExp.new/1`, which raises `ArgumentError`
on PCRE-only syntax such as `\A` or `(?i)`, and Static and LiveView match it as
the browser does. Pass a `Playwright.RegExp` for JavaScript-only syntax. Two
differences stay: without the `u` modifier the browser matches UTF-16 code units and
Static and LiveView match code points, so `~r/^.$/` matches an emoji only on Phoenix.
And on OTP 27, Static and LiveView let `\w` and `\b` also match Latin-1 letters such as
`é` (OTP 27's PCRE tables); from OTP 28 they are ASCII, as in JavaScript.

Refine a locator with `filter`, `first`, `last`, or zero-based `nth`.
Use `and_` to require both locators to match the same element:

```elixir
email = by_css("#email") |> and_(by_label("Email", exact: true))
```

The right locator resolves from the original query root, not inside the left
matches. Inside a `has` or `has_not` filter, it resolves from that filter's
candidate. Intersections preserve the left locator's order and can be chained.
For frames, the right locator can be relative to the left locator's frame or
use the same frame prefix. Playwright validates frame compatibility when the
locator resolves; intersections across different frames are unsupported.

Use `Fluffy.Locator.or_/2` to match elements found by either locator, once each in
document order. Actions stay strict, so they fail if the result is more than one element:

```elixir
accio = by_role(:button, name: "Accio") |> or_(by_role(:link, name: "Accio"))
```

`Fluffy.Locator.within/2` scopes a locator to each match of another. Unlike a scoped
`by_css(parent, "td")`, where a following `nth`, `first`, or `last` picks from all the
matches together, it picks separately inside each match, so this matches the third cell
of every row:

```elixir
third_cells = by_css("td") |> nth(2) |> within(by_css("tr"))
```

CSS `:checked` matches current checkbox, radio, and option state, including
changes made by `check`, `uncheck`, and `select_option`, but for the current selection
prefer `by_label("House") |> by_role(:option, selected: true)`.
Attribute selectors such as `[checked]` and `[selected]` still match the
rendered HTML attributes, which can differ from the user's input.

Focus requires Playwright, and LiveView renders can replace local input state; see
[Focus and client state](capabilities.md#focus-and-client-state).

Single-target actions and native visibility assertions are strict: if a locator
matches more than one element, Fluffy reports the ambiguity instead of choosing
for you. Facade `assert_has` accepts any visible match, and `refute_has` requires
no visible matches. Narrow the locator, or use `assert(count(locator, n))` when
multiple matches are the intended assertion.

### Role shorthands

`Fluffy.Locator.Roles` has `button`, `link`, and `heading`. These Fluffy shorthands
need their own import. `button("Play flute")` is `by_role(:button, "Play flute")`
and takes the same options. Pass a locator or frame scope first to match inside it.

`Phoenix.Component` exports `link/1` and a generated
`CoreComponents` exports `button/1`; where a module imports them, write
`import Phoenix.Component, except: [link: 1]` and
`import MyAppWeb.CoreComponents, except: [button: 1]`, or call `Fluffy.Locator.Roles.button/2`
in full.

```elixir
import Fluffy.Locator.Roles

session
|> click(button("Play flute"))
|> click(by_role(:navigation) |> link("Owlery", exact: true))
|> assert_has(heading("Owlery", level: 2))
```

## Frames (Playwright only)

Use a frame locator to query elements inside an iframe. Frame locators are lazy;
Playwright resolves the frame and target when an action or assertion runs. See
[Playwright's FrameLocator API](https://playwright.dev/docs/api/class-framelocator)
for the underlying browser behavior.

```elixir
gringotts = frame_locator("#gringotts")
email = by_label(gringotts, "Email")

session
|> fill(email, "griphook@gringotts.example")
|> assert(value(email, "griphook@gringotts.example"))
|> click(by_role(gringotts, :button, name: "Withdraw"))
```

Each frame boundary is strict: if multiple iframes match, an action or assertion inside
that frame fails with a strictness error. Narrow the iframe locator, or select a
particular match with `Fluffy.Locator.first/1` or `Fluffy.Locator.nth/2` before
converting it with `Fluffy.Locator.content_frame/1`:

```elixir
gringotts = by_title("Gringotts") |> first() |> content_frame()
vault = frame_locator(gringotts, "#vault")
withdraw_button = by_role(vault, :button, name: "Withdraw")
iframe_element = Fluffy.FrameLocator.owner(gringotts)
```

The `by_*` builders return ordinary element locators that support existing actions,
filters, and assertions. `Fluffy.FrameLocator.owner/1` returns the iframe element in its
containing document. As in Playwright JS, `has` and `has_not` filter operands must
remain in the same frame and cannot themselves traverse frames.

A frame locator never changes the active page. Page URL/title assertions and
navigation helpers continue to target the page's main frame. Child navigation
leaves that page state unchanged; navigation targeting `_top` updates it normally.

Static and LiveView raise `Fluffy.CapabilityError` for frame traversal; see
[Tabs, windows, and iframes](capabilities.md#tabs-windows-and-iframes).
