# Why Fluffy

Feature tests should run without a browser where they can and in one where they must, and a test
should behave the same either way. The browser side should keep up with Playwright. Fluffy runs
both through one Playwright-shaped API, and checks its in-process drivers against the browser.

You pick the backend, per session: `start_session(:phoenix)` runs the test in-process,
`start_session(:playwright)` in a browser. To pick it by tag, have your setup read one
([Shared test case](usage.md#shared-test-case)); Fluffy reads no tag to pick it and never starts a
browser on its own. Inside `:phoenix`, Fluffy picks the Static or LiveView driver by the page
visited, as PhoenixTest does.

```elixir
setup context do
  %{session: start_session(context[:backend] || :phoenix)}
end

@tag backend: :playwright
test "Fluffy falls asleep to the flute", %{session: session} do
  session
  |> visit("/creatures/fluffy")
  |> click(by_role(:button, name: "Play flute"))
  |> assert(visible(by_text("Asleep")))
end
```

Pick a browser for what Phoenix sessions can't do: they run no JavaScript and compute no CSS,
layout or focus. Browser-only features raise `Fluffy.CapabilityError` on Phoenix, but some
differences are silent: LiveView ignores `phx-debounce` and `phx-throttle`, and Phoenix acts
inside an `inert` element where Playwright waits. [Boundaries](capabilities.md#boundaries) lists
them.

## For test authors

Fluffy is the successor to PhoenixTest.Playwright, by the same author. It keeps what
PhoenixTest.Playwright already had: async browser tests with the Ecto sandbox, a browser pool,
logging in with a signed session cookie (`Fluffy.add_session_cookie/3`, now on both backends), and
traces and screenshots, which it recorded for failed tests by rerunning them with `--failed`.
Compared with PhoenixTest and PhoenixTest.Playwright, it adds:

1. **Waiting by default.** LiveView assertions retry until their deadline, and supported LiveView
   actions wait for their target to appear or become enabled; in the browser, Playwright waits as usual.
   Static pages don't change, so they are checked once. PhoenixTest's `timeout:` defaults to `0`
   and works only for LiveView assertions.
   See [Actionability checks and waiting](actions.md#actionability-checks-and-waiting).
2. **LiveView connection.** In the browser, Fluffy waits for every LiveView on the page to connect
   and join after each navigation: a `visit`, and a click or submit that navigates. No
   `assert_has("body .phx-connected")` after each visit.
   See [Actionability checks and waiting](actions.md#actionability-checks-and-waiting).
3. **Phoenix and browser tests side by side.** Tests in one module can use either backend, picked
   by tag in your setup. A test that starts no browser session takes no browser, and no Playwright
   driver or browser starts until a session needs one.
   See [Phoenix and browser tests in the same module](migration-from-phoenix-test.md#phoenix-and-browser-tests-in-the-same-module).
4. **Pages, popups and frames.** In the browser, follow popups and new tabs, switch between pages,
   and query iframes with frame locators. Download events work on every driver.
   See [Pages, popups, and frames](advanced-events.md#pages-popups-and-frames) and
   [Downloads](advanced-events.md#downloads).
5. **The whole page on LiveView.** The LiveView driver sees the root layout, `live_title`
   updates and portal content, not only the LiveView's own markup.
   See [LiveView document and patch boundaries](capabilities.md#liveview-document-and-patch-boundaries).
6. **Playwright locators on every driver.** `by_role`, `by_label`, `by_text` and the other
   locators, with regex names, work on Static and LiveView too, computing roles and accessible
   names from the markup. See [Locators](locators.md#locators).
7. **More of Playwright.** The fake clock, request routing, keyboard and mouse input, storage
   state, aria snapshot and screenshot assertions, and events for requests, responses, console
   messages and dialogs. See [Playwright coverage](capabilities.md#playwright-coverage).
8. **No Node.js setup.** `mix playwright.install` installs the pinned Playwright driver, which
   brings its own Node.js, and the browsers. There is no npm package or assets directory to keep.
   See [Playwright setup](installation.md#playwright-setup).
9. **Playwright Test in ExUnit.** Options per config, module, describe block or test; separate
   action, navigation and expect timeouts, bounded by the test's timeout, which fails a hung call
   with its call log; an `error-context.md` for failed tests and, with `trace:
   :retain_on_failure` and `screenshot: :only_on_failure`, their traces and screenshots, so there's no
   rerun to get them; assertions and `Fluffy.step/3` as trace steps; and GitHub annotations for
   failed tests.
   See [Configuration](installation.md#configuration), [Timeouts](installation.md#timeouts) and
   [Operation failures and browser diagnostics](debugging.md#operation-failures-and-browser-diagnostics).
10. **Sandbox teardown without a delay to tune.** Before the sandbox owner stops, the test waits
    for the LiveViews its browser sessions connected to exit, so their `terminate/2` can still use
    the database, and PhoenixTest.Playwright's `ecto_sandbox_stop_owner_delay` isn't needed.
    See [Ecto sandbox](installation.md#ecto-sandbox).

## How Fluffy stays correct

- **The browser is the oracle.** Hundreds of tests in `test/conformance` run the same test on a
  Phoenix driver and in Playwright, so Static and LiveView are held to what the browser does.
- **A capability matrix.** `Fluffy.Capability` lists each feature with its status on each Phoenix
  driver: equivalent (verified against Playwright), a structural subset, or browser-only. The
  [capability matrix](capabilities.md) is rendered from it, and a test keeps the two in sync.
- **Playwright drift.** `test/playwright_members_test.exs` classifies every member and event of
  the Playwright modules Fluffy builds on, and fails when Playwright adds or removes one.
- **A Playwright port.** Fluffy runs on [playwright_ex](https://hex.pm/packages/playwright_ex),
  by the same author, a 1:1 port of Playwright's JavaScript client, versioned with Playwright and
  checked against upstream by its parity task.
- **LiveViewTest underneath.** The Phoenix drivers build on `Phoenix.ConnTest` and
  `Phoenix.LiveViewTest` rather than reimplementing them, and work around them where a test would
  see the browser behave differently.

## Switching from…

Whatever you come from, check the Elixir, Phoenix and LiveView versions in
[Elixir dependency](installation.md#elixir-dependency). Every test module uses
`Playwright.Test`, Phoenix-only ones too: it runs the setup, options and timeouts.

### PhoenixTest

The `Fluffy.PhoenixTest` facade keeps most calls as they are, and Fluffy is stricter in a few
places. [Coming from PhoenixTest](migration-from-phoenix-test.md) lists what to change and check.

### PhoenixTest.Playwright

The same facade covers PhoenixTest's API; the setup, the config and the extra helpers change.
[Coming from PhoenixTest.Playwright](migration-from-phoenix-test.md#coming-from-phoenixtest-playwright)
maps them.

### Wallaby

There is no facade: tests move to Fluffy's API, with `Query.css` becoming `by_css` and
`Query.button` or `Query.link` becoming `by_role`. Wallaby's queries already retry; you gain no
chromedriver to keep in step with Chrome, Playwright's actionability waits and the LiveView
connection waits for actions, traces and an `error-context.md` for failed tests, and in-process sessions,
with the same calls, for tests that don't need a browser. Start from
[Your first test](usage.md#your-first-test) and [Locators](locators.md#locators).

### Phoenix.ConnTest and Phoenix.LiveViewTest

Fluffy builds on them, so it adds a layer rather than replacing them. Tests act as a user does,
clicking a button by its name instead of `render_click(element(view, ...))`, follow redirects and
navigation between LiveViews and controller pages, see the whole page, and can run in a browser.
In return you take on another API on top, and `Playwright.Test` in every module.
Driver-native calls stay reachable through [`Fluffy.unwrap/2`](debugging.md#native-escape-hatch).
