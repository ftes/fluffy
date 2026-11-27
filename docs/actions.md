# Actions and waiting

The snippets assume the imports from [Your first test](usage.md#your-first-test) and an initialized `session`.

## Actions and assertions

Act on the control, then assert the result:

```elixir
session
|> visit("/creatures/fluffy")
|> fill(by_label("Keeper"), "Rubeus Hagrid")
|> check(by_label("Flute ready"))
|> select_option(by_label("Status"), %{label: "Asleep"})
|> click(button("Save creature"))
|> assert_has(by_text("Creature saved"))
```

`fill` converts any `String.Chars` value to text; `clear` empties the field.
Use `set_checked` when the desired checkbox state is a boolean variable.
Assert an unchecked control with `assert(checked(locator, checked: false))`.
Checking for `indeterminate: true` requires Playwright.

### Selects and options

```elixir
house = by_label("House", exact: true)
ravenclaw = by_role(house, :option, "Ravenclaw", exact: true)

session
|> assert(attached(ravenclaw))
|> assert(count(by_role(house, :option), 4))
|> select_option(house, %{label: "Ravenclaw"})
|> assert(value(house, "ravenclaw"))
|> assert(text(by_role(house, :option, selected: true), "Ravenclaw"))
```

**Available choices:** `attached` checks that the named option exists; `count` checks
how many the select offers. Use `refute(attached(option))` for an absent choice.
A closed dropdown's options have no visible box; a list box (`multiple` or
`size` greater than 1) displays its options. Role queries exclude `aria-hidden`
options. To count every option in the DOM, use `by_css(house, "option")`.

**Current selection:** act on the select, then assert its value or the selected
option's text. For a multiple select, pass the complete list of choices and assert
`values` instead of `value`. A bare string matches either value or label; see
`Fluffy.select_option/4` for explicit value, label, and index requests.

A `<datalist>` and its options are never rendered: fill its input with an option's value,
and find the options with `count/2` or `by_role(:option, include_hidden: true)`, whose
`selected:` follows their `selected` attribute.

### Actionability checks and waiting

```elixir
session
|> fill(by_label("Potion name"), "Polyjuice Potion")
|> click(button("Save potion"))
|> assert(page_url("/potions"))
```

Click directly and assert the outcome. Playwright waits for each action's
prerequisites; for example, the button must be stable and receive pointer events.
A Playwright visit also waits for every LiveView root (including nested views)
to join. Assert application-specific results separately.

Static checks once. LiveView assertions retry on fresh renders; actions retry
missing targets and the conditions below, except that `set_input_files` checks
once. Pass `timeout:` to override the [configured deadline](installation.md#timeouts)
(Playwright's timeout or `phoenix_backend_timeout`). Both Phoenix drivers require
one target and check HTML structure and control state:

| Action | Phoenix checks | LiveView also retries while… |
| --- | --- | --- |
| `click` | enabled; no `hidden` attribute on the target | the target is disabled or hidden |
| `fill` | enabled, supported editable control, not readonly | the target is disabled or readonly |
| `check` / `uncheck` | checkbox/radio type; enabled when changing state | the target is disabled and needs changing |
| `select_option` | enabled select; requested options exist and are enabled | the select is disabled or a requested option is missing |
| `set_input_files` | file input; multiple files require `multiple` | checks immediately, including target lookup |

Ambiguity and invalid control types fail immediately. A checkbox already in the
requested state needs no change; unchecking a checked radio is invalid.
Phoenix does not compute layout or overlap: `fill` does not check visibility,
and `set_input_files` accepts hidden or disabled inputs. The locator may still
exclude hidden elements; see [Visibility and DOM presence](assertions.md#visibility-and-dom-presence).
Assert `enabled` separately if enablement itself matters; it does not imply visibility.

### Form submission and keyboard actions

```elixir
session
|> fill(by_label("Owl message"), "Meet me in the Owlery")
|> click(button("Send by owl"))
|> assert_has(by_text("Message sent"))
```

Click the intended submit button to include its `name=value` and honor overrides
such as `formaction`. Use `submit(form_locator)` to submit without a specific
button. Controls submit in document order with their current names, values, and
form owners. Removed and disabled controls are omitted; readonly and hidden
controls are included, and duplicate names keep their order. See
[Forms and files](capabilities.md#forms-and-files) for validation and reset behavior.

Use Playwright to submit implicitly with `press(locator, "Enter")` or edit text
with `"Backspace"`. On LiveView, `press` invokes bound key handlers only; Static
does not support it. See [LiveView timing and keyboard events](capabilities.md#liveview-timing-and-keyboard-events).

### Playwright-only actions

`Fluffy.Playwright` wraps more of Playwright's actions, such as `dblclick`, `tap`,
`dispatch_event`, `select_text`, `scroll_into_view_if_needed`, element `screenshot`,
`set_viewport_size`, and `emulate_media`. `Fluffy.Playwright.Keyboard` and
`Fluffy.Playwright.Mouse` send page-wide input. Each returns the session, except
`screenshot`, which returns the image as in Playwright, and raises
`Fluffy.CapabilityError` on Phoenix:

```elixir
import Fluffy.Playwright
alias Fluffy.Playwright.Keyboard

session
|> set_viewport_size(%{width: 390, height: 844})
|> emulate_media(color_scheme: :dark)
|> dblclick(by_role(:cell, "Fluffy"))
|> Keyboard.press("Enter")
|> assert_has(by_text("Fluffy's chamber"))
|> screenshot(by_css("table"), path: "tmp/creatures.png")
```

As in Playwright, page-wide input and `dispatch_event` do not wait for a navigation
they start: they can return before it commits, and an action right after them can
act on the old page or before a LiveView connects. If the input navigates, assert
something on the new page first, as above; the session adopts the new document
then.

`Fluffy.Playwright.tap/3` needs `browser_context: [has_touch: true]` and takes a
required option list, so `import Fluffy.Playwright` leaves `Kernel.tap/2` usable.

`Fluffy.Playwright.hover/3`, `Fluffy.Playwright.drag_to/4`, and
`Fluffy.Playwright.press_sequentially/4` also require Playwright. They accept `timeout:`
and the options of the matching `Playwright.Locator` action, and reconcile navigation
the action causes. Sequential typing emits keyboard events for each character and appends
at the current caret position. Drag source and target must belong to the same frame.

## Reading values

To use a value from the page in the test, read it, as with Playwright's locator reads.
They work on every driver:

```elixir
chamber = text_content(session, heading("Chamber of Secrets", level: 1))
href = get_attribute(session, link("Diagon Alley"), "href")
owl = input_value(session, by_label("Owl"))
creatures = all_text_contents(session, by_role(:listitem))
page_title = title(session)
```

`text_content` is the DOM's text, hidden and `<script>` text included; `get_attribute`
reads the HTML attribute, or `nil` without it; `input_value` reads an input, textarea or
select as `fill` and `select_option` left it. Each takes one strict target, while
`all_text_contents` reads every match, without waiting, and `all` returns a locator for
each. `title` reads the page's `<title>` and `content` its HTML
([Page content](capabilities.md#page-content)).
The browser's rendered text, `Fluffy.Playwright.inner_text/3` and `all_inner_texts/2`,
requires Playwright.

A read waits for its target to attach, as an action does, then reads the value once; it
doesn't wait for the value to change. To check a value, use an assertion, which retries
until it passes: `assert(text(by_role(:status), "Creature saved"))` rather than comparing what
`text_content` returned right after an action. To wait for an element before acting,
without asserting, use `Fluffy.wait_for/3` with a locator and `state:`.

## Reloading

Use `Fluffy.reload/1` to reload the active document:

```elixir
session
|> visit("/chambers/secrets")
|> assert_has(heading("Chamber of Secrets"))
|> reload()
|> assert_has(heading("Chamber of Secrets"))
|> assert(page_url("/chambers/secrets"))
```

The Phoenix backend dispatches the current URL again and selects the driver for the
returned document. The Playwright backend uses the page's native reload.
`Fluffy.reload/1` promises a fresh document, not preservation of unsaved client-side
state.

## Files and uploads

The same public action covers ordinary multipart forms and the supported
managed LiveView upload lifecycle:

```elixir
session
|> set_input_files(by_label("Evidence"), ["diary-front.pdf", "diary-back.pdf"])
|> click(button("Upload"))
```

The named fixture files must exist. The path list preserves selection order. Pass `[]` to clear the input. Use a
typed in-memory payload for generated bytes or a remote browser:

```elixir
payload = %Fluffy.FilePayload{
  name: "potion-ledger.csv",
  bytes: "potion,vials\nPolyjuice Potion,3\n",
  content_type: "text/csv"
}

session
|> set_input_files(by_label("Potion ledger"), payload)
|> click(button("Upload"))
```

One path or payload, a homogeneous list of either, and `[]` are accepted.
Fluffy validates and snapshots the complete selection before changing the
page. See [Upload limits](installation.md#upload-limits) for the aggregate
limit and per-action override. Error messages and diagnostic artifacts do not
copy payload contents.

Playwright can also capture a script-opened chooser before the triggering click. Pass
the chooser directly to `Fluffy.set_input_files/3`; see [Advanced events and
pages](advanced-events.md#file-choosers).

## Playwright-only evaluation

Use `Fluffy.Playwright.evaluate/3` when a Playwright test needs a value from
the active page:

```elixir
import Fluffy.Playwright

data_url = evaluate(session, "document.querySelector('canvas').toDataURL()")
assert data_url =~ "data:image/png"

session
|> click(button("Reveal diary message"))
```

`Fluffy.Playwright.evaluate/2` returns the JavaScript result, not the session, and
leaves the session as it was. To assert on page state, prefer `Fluffy.Assert`, which
retries. A function expression receives the optional `arg` of
`Fluffy.Playwright.evaluate/3`, as in `Playwright.Frame.evaluate/3`. Phoenix sessions
raise a capability error because Phoenix does not execute client code.

## Controlling time

On Playwright, `Fluffy.Playwright.Clock.install/2` fakes the page's `Date` and
timers (`setTimeout`, `setInterval`, `requestAnimationFrame`, and so on) for every
page of the session, including documents loaded later. Install the clock before
visiting the page, then pause it and advance it explicitly:

```elixir
use Fluffy.Assert
import Fluffy
import Fluffy.Locator

alias Fluffy.Playwright.Clock

session
|> Clock.install(time: ~U[2024-02-02 08:00:00Z])
|> visit("/spellbook")
|> Clock.pause_at(~U[2024-02-02 09:00:00Z])
# The search input has phx-debounce="500": nothing is sent yet.
|> fill(by_label("Search"), "Lumos")
|> Clock.run_for(500)
|> assert_has(by_text("1 spell found"))
```

`Fluffy.Playwright.Clock.run_for/3` fires every timer due on the way,
`Fluffy.Playwright.Clock.fast_forward/3` jumps ahead firing due timers once, and
`Fluffy.Playwright.Clock.resume/2` lets time flow again.
`Fluffy.Playwright.Clock.set_fixed_time/3` freezes only `Date`;
`Fluffy.Playwright.Clock.set_system_time/3` shifts it without firing timers. Timer-started navigation is adopted, as after an action.

While the clock is paused, actions, assertions, and navigation keep working:
Fluffy's waits do not use page timers. The application's own timers are frozen
though: LiveView's `phx-debounce` and `phx-throttle`,
`Phoenix.LiveView.JS.transition/2` (which also holds back LiveView's DOM updates until it ends), page title updates, and the
socket's heartbeat and reconnects. An assertion that depends on them fails
after its timeout until the test advances or resumes the clock. Phoenix sessions
raise `Fluffy.CapabilityError`.
