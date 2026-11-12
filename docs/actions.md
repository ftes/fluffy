# Actions and waiting

The snippets assume the imports from [Your first test](usage.md#your-first-test) and an initialized `session`.

## Actions and expectations

Actions and expectations use the same API on both backends:

```elixir
session
|> visit("/creatures/fluffy")
|> fill(by_label("Keeper"), "Rubeus Hagrid")
|> check(by_label("Flute ready"))
|> select_option(by_label("Status"), %{label: "Asleep"})
|> click(by_role(:button, name: "Save creature"))
|> assert(enabled(by_role(:button, name: "Save creature")))
|> assert(disabled(by_label("Species")))
|> assert(value(by_label("Keeper"), "Rubeus Hagrid"))
|> assert(editable(by_label("Keeper")))
|> assert(checked(by_label("Flute ready")))
|> assert(visible(by_text("Creature saved")))
```

`clear` empties a text input or textarea, like `fill` with `""`. `set_checked`
takes the desired state as a boolean, for a test that computes it. Both work on
every driver.

`fill` accepts any value implementing `String.Chars`, such as numbers, dates,
and custom structs. `select_option` also converts option values and labels,
including those in `%{value: value}` and `%{label: label}` requests. Conversion
uses `to_string/1` without HTML escaping; `%{index: index}` remains numeric.
Lists in `select_option` represent multiple options. To select a single
charlist value, use `%{value: charlist}` (or `%{label: charlist}` for its label).

Use `checked(locator, checked: false)` for an unchecked control. The
browser-owned indeterminate state is Playwright-only:

```elixir
session
|> assert(checked(by_label("All ingredients"), indeterminate: true))
```

Static and LiveView raise `Fluffy.CapabilityError` for indeterminate state.

### Actionability checks and waiting

LiveView expectations observe fresh renders and retry until they pass or reach
their deadline. Supported LiveView actions also retry transient missing or
actionability failures, as listed below. Waiting is enabled by default; pass
`timeout:` to an action or expectation to change its deadline. It defaults to the
session's `timeout:` from `Fluffy.start_session/2`, then the backend's
[configured timeout](installation.md#timeouts). Static checks
are immediate. Playwright uses the browser's native waiting behavior.

When a Playwright visit finds LiveView roots, it waits for every root, including
nested views, to connect and finish joining. Application-specific loading may
still need an assertion.

Playwright already checks each action's prerequisites and waits automatically
for the target to be ready. As elsewhere in Fluffy, Playwright is the model we
follow, with the Phoenix-specific limits described below. Usually you can act
directly and assert the result, without first asserting that the target is ready:

```elixir
session
|> fill(by_label("Potion name"), "Polyjuice Potion")
|> click(by_role(:button, name: "Save potion"))
|> assert(page_url("/potions"))
```

The Phoenix backend checks HTML structure and control state. Each action
requires exactly one matching target, with these additional checks:

| Action | Phoenix checks | LiveView also retries while… |
| --- | --- | --- |
| `click` | enabled; no `hidden` attribute on the target | the target is disabled or hidden |
| `fill` | enabled, supported editable control, not readonly | the target is disabled or readonly |
| `check` / `uncheck` | checkbox/radio type; enabled when changing state | the target is disabled and needs changing |
| `select_option` | enabled select; requested options exist and are enabled | the select is disabled or a requested option is missing |
| `set_input_files` | file input; multiple files require `multiple` | checks immediately, including target lookup |

For `click`, `fill`, `check` / `uncheck`, and `select_option`, LiveView also
retries missing targets until the action deadline. Ambiguous locators and invalid control types fail immediately. Static checks immediately
without waiting for later changes. A checkbox already in the requested state
needs no mutation; unchecking a checked radio is invalid.

These are action-specific rules, not a blanket visibility requirement. Phoenix
`fill` does not check visibility, and `set_input_files` intentionally accepts
hidden or disabled file inputs. Locator matching may itself exclude hidden
elements; see [Visibility and DOM presence](assertions.md#visibility-and-dom-presence).

Phoenix does not compute CSS layout or detect overlapping elements.
Playwright uses the browser's action-specific checks: for example, `fill`
waits for rendered visibility, enablement, and editability, while `click`
also waits for stability and the target to receive pointer events.

Keep separate assertions when the state itself is the behavior under test, such as a
button becoming enabled after a required field is filled. `assert(enabled(locator))`
does not imply visibility, and neither does `refute(disabled(locator))`; the latter is
the same negation as `assert(not_(disabled(locator)))` with `Fluffy.Expect.not_/1`
imported.

### Form submission and keyboard actions

Use `submit(form_locator)` when the intent is native form submission without a
specific submitter. Click the intended submit button when its `name=value` or
override attributes matter. `press(locator, "Enter")` performs implicit form submission only with Playwright.
Submissions use the latest DOM ownership and control state in document order.
Removed or disabled controls are omitted; renamed and newly inserted controls
use their current names and owners. Duplicate names preserve their order,
hidden inputs remain independent entries, and readonly controls submit even
though they cannot be filled. Multiple selections replace the selected set.
See [Forms and files](capabilities.md#forms-and-files) for validation, reset-button,
and serialization boundaries.

`Fluffy.press/4` presses natively with Playwright, only invokes bound key handlers
with LiveView, and is unsupported on Static; see
[LiveView timing and keyboard events](capabilities.md#liveview-timing-and-keyboard-events).

```elixir
# LiveView: invoke bound handlers with key = "Backspace"; do not delete text.
session |> press(by_label("Search"), "Backspace")

# Playwright: select the text, then delete it through native keyboard behavior.
session
|> press(by_label("Search"), "ControlOrMeta+A")
|> press(by_label("Search"), "Backspace")
```

For character-by-character browser typing, use `Fluffy.Playwright.press_sequentially/4`.

### Browser-only actions

`Fluffy.Playwright` wraps more of Playwright's actions, such as `dblclick`, `tap`,
`dispatch_event`, `select_text`, `scroll_into_view_if_needed`, element `screenshot`,
`set_viewport_size`, and `emulate_media`. `Fluffy.Playwright.Keyboard` and
`Fluffy.Playwright.Mouse` send page-wide input. Each returns the session and
raises `Fluffy.CapabilityError` on Phoenix:

```elixir
alias Fluffy.Playwright
alias Fluffy.Playwright.Keyboard

session
|> Playwright.set_viewport_size(%{width: 390, height: 844})
|> Playwright.emulate_media(color_scheme: :dark)
|> Playwright.dblclick(by_role(:cell, name: "Fluffy"))
|> Keyboard.press("Enter")
|> assert(visible(by_text("Fluffy's chamber")))
|> Playwright.screenshot(by_css("table"), "tmp/creatures.png")
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
and the options of the matching `PlaywrightEx.Locator` action, and reconcile navigation
the action causes. Sequential typing emits keyboard events for each character and appends
at the current caret position. Drag source and target must belong to the same frame.

## Reloading

Use `Fluffy.reload/1` to reload the active document:

```elixir
session
|> visit("/chambers/secrets")
|> assert(visible(by_role(:heading, name: "Chamber of Secrets")))
|> reload()
|> assert(visible(by_role(:heading, name: "Chamber of Secrets")))
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
|> click(by_role(:button, name: "Upload"))
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
|> click(by_role(:button, name: "Upload"))
```

One path or payload, a homogeneous list of either, and `[]` are accepted.
Fluffy validates and snapshots the complete selection before changing the
page. See [Upload limits](installation.md#upload-limits) for the aggregate
limit and per-action override. Error messages and diagnostic artifacts do not
copy payload contents.

Playwright can also capture a script-opened chooser before the triggering click. Pass
the chooser directly to `Fluffy.set_input_files/3`; see [Events and
pages](advanced-events.md#file-choosers).

## Browser-only evaluation

Use `Fluffy.Playwright.evaluate/3` when a Playwright test needs a value from
the active page:

```elixir
alias Fluffy.Playwright

session
|> then(fn session ->
  data_url = Playwright.evaluate(session, "document.querySelector('canvas').toDataURL()")

  assert data_url =~ "data:image/png"
  session
end)
|> click(by_role(:button, name: "Reveal diary message"))
```

`Fluffy.Playwright.evaluate/3` returns the JavaScript result, not the session. Use
`then/2`, as above, to continue a pipeline. A function expression receives the
optional third argument, as in `PlaywrightEx.Frame.evaluate/3`. Phoenix sessions raise a capability error because
Phoenix does not execute client code.

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
|> assert(visible(by_text("1 spell found")))
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
