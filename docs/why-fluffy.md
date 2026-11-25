# Why Fluffy

One test, with or without a real browser, through one Playwright-shaped API.

- ✅ **[Fast tests and browser tests, one library.](usage.md#shared-test-case)** Each test starts in-process or in Chromium,
  Firefox or WebKit, usually from a tag your setup reads; use a browser for JavaScript, CSS, layout
  or focus.
- ✅ **[No waits to sprinkle.](actions.md#actionability-checks-and-waiting)** Fluffy waits for the page and for LiveView to connect: no sleeps, no
  `phx-connected` checks.
- ✅ **[Find elements as a user does.](locators.md#locators)** By role, label and text, with or without a browser.
- ✅ **[Failures you can debug.](debugging.md#operation-failures-and-browser-diagnostics)** A call log, an `error-context.md`, and opt-in traces and
  screenshots from the failing run itself.
- ✅ **[No Node.js.](installation.md#playwright-setup)** `mix playwright.install` fetches the driver and the browsers.
- ✅ **[Fast tests you can trust.](#how-fluffy-stays-correct)** Fluffy's own CI checks its browser-free drivers against a real
  browser, so they behave like it, within [documented limits](capabilities.md#boundaries).

```text
                         your test
             visit · click · fill · assert(visible(…))
                             │
                       Fluffy's API
              ┌──────────────┴───────────────┐
   start_session(:phoenix)       start_session(:playwright)
              │                              │
    Static and LiveView drivers         Playwright
    on Phoenix.LiveViewTest       Chromium · Firefox · WebKit
              ▲                              │
              └──────────────────────────────┘
        Fluffy's own CI runs each conformance test
        on both and requires the same result
```

## Compared with

<table style="border-collapse: collapse">
<thead>
<tr>
<th style="text-align: left; vertical-align: bottom; border: none"></th>
<th style="height: 11em; width: 2.4em; min-width: 2.4em; padding: 0; border: none; white-space: nowrap; vertical-align: bottom"><div style="transform: translate(1.2em, -0.4em) rotate(-45deg); transform-origin: bottom left; width: 2.4em"><span style="border-bottom: 1px solid currentColor; padding: 0 0.3em">PhoenixTest + PT.Playwright</span></div></th>
<th style="height: 11em; width: 2.4em; min-width: 2.4em; padding: 0; border: none; white-space: nowrap; vertical-align: bottom"><div style="transform: translate(1.2em, -0.4em) rotate(-45deg); transform-origin: bottom left; width: 2.4em"><span style="border-bottom: 1px solid currentColor; padding: 0 0.3em">Wallaby</span></div></th>
<th style="height: 11em; width: 2.4em; min-width: 2.4em; padding: 0; border: none; white-space: nowrap; vertical-align: bottom"><div style="transform: translate(1.2em, -0.4em) rotate(-45deg); transform-origin: bottom left; width: 2.4em"><span style="border-bottom: 1px solid currentColor; padding: 0 0.3em">ConnTest + LiveViewTest</span></div></th>
<th style="height: 11em; width: 2.4em; min-width: 2.4em; padding: 0; border: none; white-space: nowrap; vertical-align: bottom"><div style="transform: translate(1.2em, -0.4em) rotate(-45deg); transform-origin: bottom left; width: 2.4em"><span style="border-bottom: 1px solid currentColor; padding: 0 0.3em">playwright_ex</span></div></th>
<th style="height: 11em; width: 2.4em; min-width: 2.4em; padding: 0; border: none; white-space: nowrap; vertical-align: bottom"><div style="transform: translate(1.2em, -0.4em) rotate(-45deg); transform-origin: bottom left; width: 2.4em"><span style="border-bottom: 1px solid currentColor; padding: 0 0.3em"><strong>Fluffy</strong></span></div></th>
<th style="border: none; min-width: 4em"></th>
</tr>
</thead>
<tbody>
<tr><td colspan="6" style="padding-top: 0.4em; font-weight: bold">Both kinds of test</td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">Tests without a browser</th><td align="center">✓<sup>1</sup></td><td align="center">–</td><td align="center">✓</td><td align="center">–</td><td align="center">✓</td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">Chromium, Firefox and WebKit</th><td align="center">✓<sup>1</sup></td><td align="center">◐<sup>2</sup></td><td align="center">–</td><td align="center">✓</td><td align="center">✓</td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">One library for both</th><td align="center">–<sup>1</sup></td><td align="center">–</td><td align="center">–</td><td align="center">–</td><td align="center">✓</td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">Same API for both</th><td align="center">◐<sup>3</sup></td><td align="center">–</td><td align="center">–</td><td align="center">–</td><td align="center">✓</td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">Pipeline API</th><td align="center">✓</td><td align="center">✓</td><td align="center">–</td><td align="center">–</td><td align="center">✓</td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">Both in one module</th><td align="center">–</td><td align="center">–</td><td align="center">–</td><td align="center">–</td><td align="center">✓</td></tr>
<tr><td colspan="6" style="padding-top: 1.4em; font-weight: bold">Without a browser</td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">Checked against a real browser</th><td align="center">◐<sup>4</sup></td><td align="center">–</td><td align="center">–</td><td align="center">–</td><td align="center">✓</td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">Auto-waiting</th><td align="center">◐<sup>5</sup></td><td align="center">–</td><td align="center">–</td><td align="center">–</td><td align="center">✓</td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">Role locators</th><td align="center">◐<sup>6</sup></td><td align="center">–</td><td align="center">–</td><td align="center">–</td><td align="center">✓</td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">The whole LiveView page</th><td align="center">◐<sup>7</sup></td><td align="center">–</td><td align="center">◐<sup>7</sup></td><td align="center">–</td><td align="center">✓</td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">LiveViews in a controller page or the layout</th><td align="center">–</td><td align="center">–</td><td align="center">◐<sup>8</sup></td><td align="center">–</td><td align="center">–</td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">LiveViewTest's own calls, such as <code>render_hook</code></th><td align="center">◐<sup>9</sup></td><td align="center">–</td><td align="center">✓</td><td align="center">–</td><td align="center">◐<sup>10</sup></td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">Scripts, computed style and other browser features</th><td align="center">–</td><td align="center">–</td><td align="center">–</td><td align="center">–</td><td align="center">–<sup>11</sup></td></tr>
<tr><td colspan="6" style="padding-top: 1.4em; font-weight: bold">In a browser</td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">Waits for LiveView to connect</th><td align="center">–</td><td align="center">–</td><td align="center">–</td><td align="center">–</td><td align="center">✓</td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">Popups, tabs and frames</th><td align="center">◐<sup>12</sup></td><td align="center">✓</td><td align="center">–</td><td align="center">✓</td><td align="center">✓</td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">Playwright's API as native calls</th><td align="center">◐<sup>13</sup></td><td align="center">–</td><td align="center">–</td><td align="center">✓</td><td align="center">✓<sup>14</sup></td></tr>
<tr><th scope="row" style="text-align: left; font-weight: normal">Sandbox teardown without a tuned delay</th><td align="center">◐<sup>15</sup></td><td align="center">–</td><td align="center">–</td><td align="center">–</td><td align="center">✓</td></tr>
</tbody>
<tfoot>
<tr><td colspan="6" style="font-size: 0.85em; border: none; padding-top: 0.8em">✓ yes · ◐ partly · – no.<br>Versions: PhoenixTest 0.14, PhoenixTest.Playwright 0.20, Wallaby 0.31, LiveView 1.2, playwright_ex 1.65.<br><sup>1</sup> Without a browser through PhoenixTest, in one through PhoenixTest.Playwright: two libraries.<br><sup>2</sup> Chrome; others through Selenium.<br><sup>3</sup> PhoenixTest.Playwright's behavior differs from PhoenixTest's in places.<br><sup>4</sup> PhoenixTest's own CI checks only the params that forms and links send, in 29 Chromium cases; assertions, locators and visibility aren't checked. The browser driver is a separate library: where it differs, PhoenixTest.Playwright skips 63 of PhoenixTest's tests.<br><sup>5</sup> Opt-in, and only for LiveView assertions.<br><sup>6</sup> Labels and text, no roles.<br><sup>7</sup> Plus <code>page_title</code>.<br><sup>8</sup> Only on its own, with <code>live_isolated</code>.<br><sup>9</sup> Through <code>unwrap</code>.<br><sup>10</sup> Through <code>unwrap</code>, which reaches only the main LiveView; see <a href="capabilities.html#liveview-document-and-patch-boundaries">LiveView boundaries</a>.<br><sup>11</sup> Calls that need a browser (<code>evaluate</code>, real input, the clock, the network, tabs and frames) raise <code>Fluffy.CapabilityError</code>; scripts, computed style and layout are silently absent. See <a href="capabilities.html#boundaries">Boundaries</a>.<br><sup>12</sup> Frames through <code>within</code>; the rest through <code>unwrap</code>.<br><sup>13</sup> A subset (screenshots, dialogs, keyboard input, <code>evaluate</code>, storage state); the rest through <code>unwrap</code>.<br><sup>14</sup> Except the few calls that would break Fluffy's page tracking, listed in <a href="capabilities.html#playwright-coverage">Playwright coverage</a>.<br><sup>15</sup> A tuned <code>ecto_sandbox_stop_owner_delay</code>.</td></tr>
</tfoot>
</table>

## How Fluffy stays correct

- **The browser is the oracle.** In Fluffy's own test suite, conformance tests run the same test on
  a Phoenix driver and in Playwright, so Static and LiveView are held to what the browser does.
  This happens when Fluffy is built and released, not in your test runs.
- **A capability matrix.** `Fluffy.Capability` records each feature's status per Phoenix driver;
  the [capability matrix](capabilities.md) is rendered from it, and a test keeps them in sync.
- **Playwright drift.** A test classifies every member and event of the Playwright modules Fluffy
  uses, and fails when Playwright adds or removes one.
- **A Playwright port.** Fluffy runs on [playwright_ex](https://hex.pm/packages/playwright_ex), a
  1:1 port of Playwright's JavaScript client, versioned with Playwright.
- **LiveViewTest underneath.** The Phoenix drivers build on `Phoenix.ConnTest` and
  `Phoenix.LiveViewTest`, and work around them only where the browser would behave differently.

## Switching

- **PhoenixTest and PhoenixTest.Playwright:** the `Fluffy.PhoenixTest` facade keeps most calls;
  [Coming from PhoenixTest](migration-from-phoenix-test.md) lists what to change.
- **Wallaby:** no facade. `Query.css` becomes `by_css`, `Query.button` and `Query.link` become
  `by_role`; start from [Your first test](usage.md#your-first-test).
- **Phoenix.ConnTest and Phoenix.LiveViewTest:** Fluffy builds on them, and native calls stay
  reachable through [`Fluffy.unwrap/2`](debugging.md#native-escape-hatch).

Every test module uses `Playwright.Test`, Phoenix-only ones too. Check the supported Elixir,
Phoenix and LiveView versions in [Elixir dependency](installation.md#elixir-dependency).
