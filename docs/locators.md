# Locators and frames

The snippets assume the imports from [Your first test](usage.md#your-first-test) and an initialized `session`.

## Locators

```elixir
session
|> fill(by_label("Name"), "Basilisk")
|> click(button("Register"))
|> assert_has(by_text("Creature registered"))
```

Use the field's label, the button's accessible name, or the text the reader should
see. If several controls have the same name, scope the action to the relevant
row, card, or form:

```elixir
potion = by_role(:row) |> filter(has: by_role(:cell, "Polyjuice Potion", exact: true))

session |> click(button(potion, "Inspect"))
```

If no user-facing name distinguishes the target, use `Fluffy.Locator.by_test_id/1`
(the attribute is configured suite-wide) or `by_css` for unnamed structure.
CSS must be valid browser CSS, including escapes for special characters in IDs.

### Combining locators

`filter(has: ...)` keeps each row containing a matching descendant. To match two
descriptions of the **same element**, use `Fluffy.Locator.and_/2`. For alternatives,
use `button("Accio") |> or_(link("Accio"))`. Single-target actions and visibility
assertions fail if both match; use `assert(count(locator, n))` to check a collection.

Use `first`, `last`, or zero-based `nth` when position matters.
`by_css("td") |> nth(2) |> within(by_css("tr"))` picks the third cell **in each
row**; `by_css("tr") |> by_css("td") |> nth(2)` picks one cell overall.

### Matching names and state

Text, labels, and role names match normalized substrings by default; pass
`exact: true` for the whole string. A valid explicit role usually overrides the
implicit one; a focusable button with `role="none"` still matches a button
(see `Fluffy.Locator.by_role/2`). For names, `aria-labelledby` takes precedence
over `aria-label`, then native labels and captions, then content where the role
allows it, then `title`. A dialog, landmark, list, or list item does not take
its name from its contents. Phoenix derives names from markup, ignoring computed
CSS and changes to control values since rendering.

`checked:` and `selected:` match current control state, as does CSS `:checked`;
`[checked]` and `[selected]` match rendered attributes. See
[Selects and options](actions.md#selects-and-options) for a selection example.
Phoenix reads other role states from markup and uses structural visibility for
`include_hidden:`. `aria-checked="mixed"` works everywhere; a JavaScript-set
`indeterminate` property requires Playwright. A state unsupported by the role
raises when the locator resolves. See [Focus and client state](capabilities.md#focus-and-client-state)
for what survives a LiveView render.

`Fluffy.Locator` lists the constructors, options, and regex rules. For example,
`by_text(~r/^Lumos$/)` matches raw text and misses `<li> Lumos </li>`, whereas
role-name regexes match normalized accessible text. Use JavaScript regex syntax
that Elixir also supports for cross-driver tests. Without `u`, `~r/^.$/`
matches an emoji on Phoenix but not in the browser (code points vs. UTF-16 code
units). On OTP 27, Phoenix `\w` and `\b` also treat Latin-1 letters as word
characters; from OTP 28 they use ASCII as in JavaScript.

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
|> click(button(gringotts, "Withdraw"))
```

Each frame boundary is strict: if multiple iframes match, an action or assertion inside
that frame fails with a strictness error. Narrow the iframe locator, or select a
particular match with `Fluffy.Locator.first/1` or `Fluffy.Locator.nth/2` before
converting it with `Fluffy.Locator.content_frame/1`:

```elixir
gringotts = by_title("Gringotts") |> first() |> content_frame()
vault = frame_locator(gringotts, "#vault")
withdraw_button = button(vault, "Withdraw")
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
