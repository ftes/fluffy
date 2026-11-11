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
|> assert(visible(by_text("Creature registered")))
```

Locators are values, so they can be scoped and reused:

```elixir
potions = by_css("#potions")
potion = by_role(potions, :row, name: "Polyjuice Potion")

session
|> click(by_role(potion, :button, name: "Inspect"))
```

Available constructors are `by_role`, `by_text`, `by_label`,
`by_placeholder`, `by_alt_text`, `by_title`, `by_test_id`, and `by_css`.
Text, role-name, and label matching default to normalized substring matching;
use `exact: true` for a complete match. Role names follow accessible-name
precedence: `aria-labelledby`, then `aria-label`, then native labels and
captions, then content for the roles Playwright names from content, then
`title`. Landmarks, lists, list items and dialogs are not named by their content.
Explicit ARIA roles override implicit roles. See `Fluffy.Locator.by_role/2` for the
implicit roles the Phoenix backend knows. Phoenix computes these from markup, so
computed CSS and live input state stay browser-only. CSS must be valid browser
CSS; escape special characters in IDs or use a semantic/test-id locator.

Options marked *Playwright only.* in `Fluffy.Locator`, such as
`by_role(:button, pressed: true)` or `by_role(:heading, level: 2)`, compile into
the browser's selector. Static and LiveView sessions raise `Fluffy.CapabilityError`
when they resolve such a locator.

`name:`, `has_text:` and `has_not_text:` also take a regular expression, as in
Playwright: `name:` tests it against the normalized accessible name, and the text
filters against the element's raw text, so `~r/^Pro$/` does not match
`<li> Pro </li>`. On Static and LiveView it runs as PCRE, and in the browser as
JavaScript, so edge cases differ: `$` also matches before a final newline on
Phoenix, and without the `u` flag `.` matches one byte there rather than one
character.

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
changes made by `check`, `uncheck`, and `select_option`. For example,
`by_label("House") |> by_css("option:checked")` locates the current selection.
Attribute selectors such as `[checked]` and `[selected]` still match the
rendered HTML attributes, which can differ from the user's input.

Focus requires Playwright, and LiveView renders can replace local input state; see
[Focus and client state](capabilities.md#focus-and-client-state).

Single-target actions and native visibility assertions are strict: if a locator
matches more than one element, Fluffy reports the ambiguity instead of choosing
for you. Facade `assert_has` accepts any visible match, and `refute_has` requires
no visible matches. Narrow the locator, or use `assert(count(locator, n))` when
multiple matches are the intended assertion.

## Frames (Playwright)

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
