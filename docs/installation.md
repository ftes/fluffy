# Installation and runtime

Add Fluffy and configure your Phoenix endpoint. If your tests use the
[Ecto sandbox](#ecto-sandbox), start a sandbox owner for either backend.
For browser tests, also [install a browser](#playwright-setup). Then run
[your first test](usage.md#your-first-test).

## Elixir dependency

Fluffy requires Phoenix 1.7.10 or later and LiveView 1.1.32 or later. Uploading several files
through one input on the Phoenix drivers needs LiveView 1.2.10, for a fix in
`Phoenix.LiveViewTest`'s upload client.

In `mix.exs`:

```diff
 defp deps do
   [
     # ...
-    {:lazy_html, ">= 0.1.0", only: :test},
+    {:lazy_html, ">= 0.1.0", only: [:dev, :test]},
+    {:fluffy, "~> 0.9.0-rc.7", only: [:dev, :test]}
   ]
 end
```

Run `mix deps.get`. Including `:dev` makes Playwright's Mix tasks available without
`MIX_ENV=test`; Fluffy needs no dev configuration and starts no browser or driver
there. If your app already lists `lazy_html`, widen its environments to match.
Playwright comes with Fluffy. Only list it separately if you
[sync usage rules](#usage-rules-for-coding-agents); its Hex package is `playwright_ex`.

## Phoenix endpoint

In `config/test.exs`, tell Fluffy which endpoint handles in-process requests.
Enable its HTTP server if you also run browser tests:

```elixir
config :fluffy, endpoint: MyAppWeb.Endpoint

config :my_app, MyAppWeb.Endpoint, server: true
```

Leave `base_url` unset for a local endpoint. Fluffy uses the endpoint's `url`
host. For the scheme and port it uses the HTTP listener first, then HTTPS,
then the configured URL if neither listener is running. This works with
`port: 0`; with `phx.new` defaults the browser visits `http://localhost:4002`.

## Configuration

The endpoint is enough to start. To change a default, choose the setting by
what the test needs:

| Setting | Phoenix session | Browser session |
| --- | --- | --- |
| `base_url`, `extra_http_headers` | yes | yes |
| `locale`, `user_agent` | as the `Accept-Language` and `User-Agent` headers a browser sends | yes |
| `test_id_attribute`, from `config :playwright, :test` only | yes | yes |
| Other context options (`viewport`, `color_scheme`, ...) | no: nothing a server sees | yes |
| [Default timeouts](#timeouts) | `config :fluffy, phoenix_backend_timeout: 1_000` | Playwright's `action_timeout`, `navigation_timeout` and `expect: [timeout: ...]` |
| Recording: trace, screenshot, video | no (steps are recorded) | yes |
| A call's `timeout:` | overrides the default | overrides the default |

Set Playwright defaults under `config :playwright, :test`. Projects, modules,
then describe or test tags can override context and action options. Each level
replaces the entire option: a tag or session that sets `extra_http_headers`
must repeat any headers it wants to keep. An explicit `accept-language` header
overrides `locale` (default `en-US`). Browser selection, launch and connection
options can be set up to the module level; `test_id_attribute` and `expect` timeout
are suite-wide. See `Playwright.Test` for its options.

```elixir
# config/test.exs
config :playwright, :test,
  action_timeout: 15_000,
  navigation_timeout: 15_000,
  expect: [timeout: 5_000]
```

```elixir
# In a module using your shared test case
@tag backend: :playwright
@tag Playwright.Test.use(action_timeout: 30_000, locale: "en-GB")
test "sends an owl in a browser", %{session: session} do
  session
  |> visit("/owlery")
  |> click(button("Send owl"))
  |> assert_has(by_text("Hedwig is on her way"))
end
```

For a test with a different endpoint or host, `start_session/2` resolves the
URL in this order: session `base_url:`, session `endpoint:`, Playwright's
resolved `base_url`, configured Fluffy endpoint. A fixed `base_url` overrides
even a dynamically assigned listener port.

## Playwright setup

Install the pinned Playwright driver and Chromium with one command:

```bash
mix playwright.install chromium
```

Chromium runs headless by default. To use Firefox or WebKit, install the matching
browser (for example, `mix playwright.install firefox`) and set
`config :playwright, :test, browser_name: :firefox` or `:webkit`. See
[Browser baseline](capabilities.md#browser-baseline) for conformance coverage.

Both backends require `use Playwright.Test` after your `ConnCase` or
`use ExUnit.Case`; the [shared test case](usage.md#shared-test-case) does this
once. A Phoenix-only test takes no browser. Each Playwright session gets an
isolated browser context, so start a second session to test a second user.
Playwright Test manages the browsers and [workers](`e:playwright:test-artifacts.md#workers`).
See [CI](#ci) for recording settings and [Troubleshooting](#troubleshooting)
for headed runs and console output.

## Ecto sandbox

Use your app's `ConnCase` or `DataCase` before `use Playwright.Test`. Keep its
generated sandbox setup on both backends: start an owner per test and stop it
in `on_exit`.

```elixir
def setup_sandbox(tags) do
  pid = Ecto.Adapters.SQL.Sandbox.start_owner!(MyApp.Repo, shared: not tags[:async])
  on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
end
```

That's enough for Phoenix: requests run in the test process and LiveViews have
it in `$callers`. **For browser tests**, the HTTP endpoint and LiveViews need
the test's sandbox metadata. Enable the test-only plug and hooks in `config/test.exs`:

```elixir
config :my_app, sql_sandbox: true
config :fluffy, ecto_repos: [MyApp.Repo]
```

Add the sandbox plug before the rest of the endpoint and expose request headers
to the LiveView socket:

```elixir
if Application.compile_env(:my_app, :sql_sandbox) do
  plug Phoenix.Ecto.SQL.Sandbox,
    header: Fluffy.Sandbox.header(),
    sandbox: Fluffy.Sandbox.allowance()
end

socket "/live", Phoenix.LiveView.Socket,
  websocket: [connect_info: [:x_headers, session: @session_options]]
```

Run the Fluffy mount hook for every LiveView from `live_view/0` in
`my_app_web.ex`:

```elixir
def live_view do
  quote do
    use Phoenix.LiveView

    if Application.compile_env(:my_app, :sql_sandbox) do
      on_mount Fluffy.Sandbox
    end

    # ...
  end
end
```

That hook runs after `live_session` hooks. If those use the database, as
authentication hooks do, also add it ahead of them in the router:

```elixir
live_session :require_authenticated_user,
  on_mount:
    if(Application.compile_env(:my_app, :sql_sandbox), do: [Fluffy.Sandbox], else: []) ++
      [{MyAppWeb.UserAuth, :ensure_authenticated}] do
  # routes
end
```

### Sandbox teardown

Sessions close in their own `on_exit`, registered after the DataCase's, so browser
contexts and in-process LiveViews close before the owner stops. Start sessions in the test
process or its `setup`: a Phoenix session started from a `Task` belongs to the test too, but
closes when the test process exits, alongside the `on_exit` callbacks, so maybe after the
owner stops. A plain `Ecto.Adapters.SQL.Sandbox.checkout/1` in the test process is not
supported for browser tests: its connection goes with the test process, before the browser
closes.

A LiveView's process exits shortly after its browser closes, so the test waits, up to 5 seconds,
for the LiveViews its browser sessions connected to exit before the owner stops: their
`terminate/2` can still use the database. This covers sessions started in the test process or its
`setup`, not from a Task. This wait runs after the test process has exited, so it
does not keep that process's Mox stubs alive. If a test action triggers work that
uses a stub, wait for that work before returning. For work triggered by browser
teardown itself, such as a `pagehide` push when the session closes in `on_exit`,
use a test adapter that stays available through teardown.

### Custom sandbox allowance or header

The defaults are the `x-fluffy-sandbox` header and
`Ecto.Adapters.SQL.Sandbox`. Applications that already use Phoenix Ecto's
`user-agent` transport or need to grant additional process ownership can
configure both values in `config/test.exs`:

```elixir
config :fluffy, Fluffy.Sandbox,
  header: "user-agent",
  sandbox: MyApp.TestSandbox
```

Sandbox metadata defaults to `trap_exit: true`, following Phoenix Ecto. Set
`trap_exit: false` in this configuration if the application must retain ordinary
exit handling, for example when linked tasks finish normally in a LiveView.

The sandbox value may be a module implementing `allow(repo, owner, child)` or
Phoenix Ecto's `{module, function, extra_arguments}` form. For example:

```elixir
defmodule MyApp.TestSandbox do
  def allow(repo, owner, child) do
    Ecto.Adapters.SQL.Sandbox.allow(repo, owner, child)
    MyApp.Mocks.allow(owner, child)
  end
end
```

Fluffy validates this configuration when its application starts. With the
`user-agent` header, list `:user_agent` in the socket's `connect_info` in place of
`:x_headers`.

### Keeping your own LiveView hook

An application may keep its own LiveView hook in place of `Fluffy.Sandbox`'s, when additional
ownership rules need application state. Pass `Fluffy.Sandbox` there, as
`Phoenix.Ecto.SQL.Sandbox.allow(metadata, Fluffy.Sandbox)`, not `Ecto.Adapters.SQL.Sandbox`:
otherwise the test doesn't wait for its LiveViews to exit, and their late database work, in
`terminate/2` or a `pagehide` push, logs ownership errors. A hook built on Phoenix Ecto's
example also calls it on the static render; that's fine, only LiveView processes are waited for.

The wait needs a session Fluffy started. Closing it waits for those LiveViews to exit. A suite that drives the
browser with playwright_ex on its own registers them, but nothing waits for them.

`Fluffy.Sandbox` grants the configured `:sandbox`, so a hook that passed its own allowance
module moves it to `sandbox:` above.

## CI

On Linux, run `mix playwright.install chromium --with-deps` to install the
browser and its system packages. To retain evidence when a browser test fails:

```elixir
# config/test.exs
config :playwright, :test,
  trace: :retain_on_failure,
  screenshot: :only_on_failure
```

Ignore `test-results/` in git and upload it when the test job fails. See
[Debugging](debugging.md) for reading a trace and `Playwright.Test` for video
and other recording options.

For GitHub annotations, include both formatters on the first test run:
`mix test --formatter ExUnit.CLIFormatter --formatter Playwright.Test.GitHubFormatter`.
The flag replaces the formatter list; include any others your suite uses.
See Playwright's [GitHub Actions workflow](`e:playwright:debugging-and-ci.md#github-actions`)
and [retry recipe](`e:playwright:test-artifacts.md#retries`). Before Elixir 1.21,
`mix test --failed` can miss a failure in an `on_exit` registered in `setup_all`.

## Remote browsers

Point Playwright Test at the server and let the browser reach the Phoenix
endpoint through your test machine's loopback interface:

```elixir
config :playwright, :test,
  connect_options: [ws_endpoint: "ws://localhost:3000/", expose_network: "<loopback>"]
```

With the tunnel, keep the endpoint-derived URL. Without it, set `base_url` to
an address the browser can reach, such as `http://host.docker.internal:4002`,
bind the endpoint's HTTP listener to an interface reachable from the browser,
and allow that origin in the endpoint's `check_origin`. A loopback-only listener
won't accept connections from another host. Both the initial
request carrying the sandbox header and the LiveView socket must reach the app.
For a port supplied at runtime, configure the override in `config/runtime.exs`
inside `if config_env() == :test`. See Playwright's
[remote browser guide](`e:playwright:test-artifacts.md#remote-browsers`) for server setup.

## Troubleshooting

**The page loads but the LiveView never connects.** Check that the app serves
its browser bundle, the bundle connects its LiveSocket, and `check_origin`
allows the browser's URL. Fluffy [waits for the LiveViews to join](actions.md#actionability-checks-and-waiting)
after navigation.

**An absolute app URL looks external in a Phoenix test.** Compare
`MyAppWeb.Endpoint.url()` with the session URL. The configured URL port must
match the listener port for these to be same-origin. A fixed test port, as in
`phx.new`, keeps them aligned; `port: 0` does not.

**A test fails only in the browser.** To watch just that test, pass a headed
browser to the session:

```elixir
browser = Playwright.Test.BrowserPool.browser(headless: false, launch_options: [slow_mo: 500])
start_session(:playwright, browser: browser) |> visit("/creatures")
```

The trace includes browser console messages and uncaught page errors. To print
console messages during the test, register a listener before the action:

```elixir
on(session, Fluffy.Event.console(), fn message ->
  IO.puts(Playwright.ConsoleMessage.text(message))
end)
```

See [Debugging](debugging.md) and Playwright's
[debugging one test](`e:playwright:test-artifacts.md#debugging-one-test`).

**The environment already supplies a browser or CLI.** In Microsoft's
`mcr.microsoft.com/playwright:v<version>-noble` image, match `<version>` to
`Playwright.Driver.version/0` and run `mix playwright.install --no-browsers`;
the driver finds the installed browsers via `PLAYWRIGHT_BROWSERS_PATH`. For a
system Chrome, set `launch_options: [executable_path: System.find_executable("google-chrome-stable")]`
or select a `channel:`. To supply the matching CLI too, set
`config :playwright, :driver, executable: "node_modules/.bin/playwright"` in
`config/config.exs`, which the install task reads in `:dev`. Point at the
executable, not `cli.js`. Browser launch has its own three-minute default
timeout; override it with `launch_options: [timeout: 10_000]`.

## Timeouts

Phoenix actions, assertions and event waits use `phoenix_backend_timeout`
(default one second); static checks run once. Browser operations use Playwright
Test's [configured timeouts](#configuration), including native calls in `unwrap`
that inherit the context's timeouts. Browser assertions default to five seconds.
Without an action or navigation timeout the ExUnit test timeout bounds the
wait (60 seconds by default).

Native assertions and event waits accept `timeout: :once` for an immediate check.
Playwright actions, locator waits and screenshot assertions reject `:once`.
Use `:infinity` for no operation deadline; the test deadline still applies.
Native calls reject `timeout: 0`. In Playwright configuration `0` means no limit;
[PhoenixTest facade assertions](migration-from-phoenix-test.md#what-stays-familiar-and-what-to-check)
use it for an immediate check.

The wait for a LiveView to connect shares the navigation timeout. Fluffy's
document checks around a browser operation share its timeout but get at least
one second to detect a blocked main thread. Operations such as `evaluate` and
reading a response body take no `timeout:` and can wait until the test times
out. See [Actionability checks and waiting](actions.md#actionability-checks-and-waiting)
for what each driver waits for.

## Upload limits

```elixir
config :fluffy, file_input_max_bytes: 10_000_000
```

`file_input_max_bytes` bounds the aggregate bytes Fluffy will snapshot for one
`Fluffy.set_input_files/3` or `Fluffy.set_input_files/4` action. It applies to local
paths and in-memory payloads on all three drivers and can be overridden with the
action's `max_bytes:` option.

## Usage rules for coding agents

Add [`usage_rules`](https://hexdocs.pm/usage_rules) to your dev dependencies.
It syncs only direct dependencies, so also list Playwright to include its rules
with Fluffy's (Fluffy's requirement selects the Playwright version):

```elixir
[
  {:usage_rules, "~> 1.3", only: :dev, runtime: false},
  {:playwright, ">= 0.0.0", hex: :playwright_ex, only: [:dev, :test]}
]
```

Keep `hex: :playwright_ex`: `playwright` on Hex is another library.
Group the feature-test rules in one skill and load Phoenix's LiveView rules
separately when writing application code. This keeps its “LiveView tests”
rules out of an always-loaded `AGENTS.md`:

```elixir
# mix.exs, in project/0
usage_rules: [
  skills: [
    build: [
      "phoenix-feature-tests": [
        description: "Use when writing or debugging Phoenix feature tests with Fluffy.",
        usage_rules: [:fluffy, :playwright]
      ],
      "phoenix-liveview": [
        description: "Use when writing LiveViews, components or templates.",
        usage_rules: ["phoenix:liveview"]
      ]
    ]
  ]
]
```

Run `mix deps.get`, then `mix usage_rules.sync` after adding or upgrading the dependencies.
