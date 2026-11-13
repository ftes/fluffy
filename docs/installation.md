# Installation and runtime

Add Fluffy and configure your Phoenix endpoint first. Complete Playwright setup
if you need browser tests, and Ecto sandbox setup if your application uses a
database. Then follow [Usage](usage.md) for your first test and shared test case.

## Elixir dependency

In `mix.exs`:

```diff
 defp deps do
   [
     # ...
-    {:lazy_html, ">= 0.1.0", only: :test},
+    {:lazy_html, ">= 0.1.0", only: [:dev, :test]},
+    {:fluffy, "~> 0.9.0-rc.2", only: [:dev, :test]}
   ]
 end
```

Prefer `only: [:dev, :test]` to `only: :test`: PlaywrightEx's Mix tasks, and
[`mix usage_rules.sync`](https://hexdocs.pm/usage_rules) for Fluffy's usage rules, then work
in `:dev`, where Fluffy needs no config and starts no driver or browser. Mix requires a
dependency you list to cover every environment Fluffy needs it in, so widen the
`lazy_html` line `phx.new` generates, if your app has it.
PlaywrightEx comes with Fluffy in the same environments, so `mix playwright_ex.install`
works without listing it. List it only to sync its usage rules, since `usage_rules.sync`
reads only the dependencies `mix.exs` lists:
`{:playwright_ex, "~> 0.17.0-rc.5", only: [:dev, :test]}`.

## Phoenix endpoint

Configure your application endpoint once in `config/test.exs`. Fluffy uses
it for in-process requests and derives the default session URL from the
endpoint. When the endpoint has an active HTTP or HTTPS listener, its actual
bind address and port are authoritative. Fluffy falls back to
`MyAppWeb.Endpoint.url()` when no listener is running. This supports endpoints
configured with `port: 0`:

```elixir
config :fluffy, endpoint: MyAppWeb.Endpoint

config :my_app, MyAppWeb.Endpoint, server: true, check_origin: false
```

The server is required for Playwright tests. The browser opens the listener's
address, such as `127.0.0.1`, which a stock `localhost` endpoint URL does not
match, so `check_origin: false` lets the LiveView socket connect. By default Phoenix
checks only the origin's host against the endpoint's `url` host, so an endpoint
with `url: [host: "127.0.0.1"]` needs no `check_origin: false`. If Playwright
targets an application hosted elsewhere, configure
`config :fluffy, base_url: "..."` instead. Explicit `endpoint:` and `base_url:`
session options override the global values for multi-endpoint or dynamic-server
tests.

The application's normal browser bundle must connect its LiveSocket. See
[Actionability checks and waiting](actions.md#actionability-checks-and-waiting)
for Fluffy's automatic LiveView connection wait.

## Timeouts

The defaults are Playwright Test's, set in PlaywrightEx's config for the whole suite, Fluffy
sessions and raw PlaywrightEx tests alike:

```elixir
config :playwright_ex, :test,
  # Actions, locator waits and event waits; `:infinity` (none) by default.
  action_timeout: 15_000,
  # `visit`, `reload`, `go_back`, `go_forward` and `wait_for_load_state`; `:infinity` by default.
  navigation_timeout: 15_000,
  # `by_test_id`'s attribute; `data-testid` by default.
  test_id_attribute: "data-owl"

# Assertions; 5 seconds by default.
config :playwright_ex, :expect, timeout: 5_000
```

Fluffy's three keys override them for Fluffy sessions on every driver; a suite without browser
tests can set just those:

| Setting | Fluffy sessions | Raw PlaywrightEx tests |
| --- | --- | --- |
| Actions | `config :fluffy, action_timeout:`, else PlaywrightEx's `action_timeout` | PlaywrightEx's |
| Assertions | `config :fluffy, expect_timeout:`, else PlaywrightEx's `:expect` `timeout` | PlaywrightEx's |
| Test id | `config :fluffy, test_id_attribute:`, else PlaywrightEx's `test_id_attribute` | PlaywrightEx's |
| Navigations | PlaywrightEx's `navigation_timeout` | PlaywrightEx's |

A forgotten Fluffy key keeps overriding a newer PlaywrightEx value. A value means what its
source says: PlaywrightEx's `0` is no limit, as in Playwright. Fluffy's are Elixir timeouts, a
positive integer or `:infinity`, and for `expect_timeout` also `0`, which checks once, as a
call's `timeout: 0`; `action_timeout` rejects `0`, as Playwright actions cannot check once. A
Playwright session sets the action and navigation timeouts on its browser context, so native
calls in an `unwrap` callback get them too.

With no action or navigation timeout, the test's timeout bounds them (ExUnit's default
is 60 seconds). On Playwright, PlaywrightEx.Test closes the test's contexts just before,
so a call that hangs fails with "Test timeout of 60000ms exceeded." and its call log. In a
test with `Fluffy.Case`, a LiveView action that never finds its element, or a Phoenix event
wait, fails at the same moment with Fluffy's error and the same reason. Phoenix-only tests
without `Fluffy.Case` have no such backstop and fail with ExUnit's timeout, so set an
`action_timeout` there. There is no per-session timeout; pass `timeout:` to a call.

An operation's `timeout: 0` checks once, unlike Playwright, where `0` disables the timeout.
Playwright assertions check once too, but Playwright actions and waits reject 0 with an
`ArgumentError`, as they cannot check once; pass a positive timeout.

For no timeout, pass `timeout: :infinity`, never Playwright's `0`. Playwright then waits
with no timeout, and LiveView retries and event waits go on until the test times out; Static
checks once, as with any timeout, since nothing on its page changes.

Fluffy's own reads of the page around a Playwright operation share its timeout, but get
at least a second: a page whose main thread is blocked takes a second to report, not a
shorter timeout. Its waits for a LiveView to connect after a navigation share the
navigation timeout.

As in Playwright, calls that have no timeout there have none in Fluffy and take no
`timeout:`: page `evaluate`, `content` and `title`, page-wide keyboard and mouse input,
clock calls, context setters, closing a page, `unroute_all`, and reading a download or a
response body. Page `evaluate`, context setters, closing a page, `unroute_all`, stopping a
trace, network and download reads, and the PhoenixTest facade's link lookup in
`click_link/4` wait on a blocked page until the test times out. The others first check the
page's document, so on a page that is already blocked they fail after the action timeout,
or a second if that is shorter, and with none at the test's timeout.

## Playwright setup

Only the Playwright backend needs a browser. PlaywrightEx pins its Playwright
driver; install it and a browser with:

```bash
mix playwright_ex.install -- chromium
```

On Linux CI runners, add `--with-deps` to install the browser's system packages too:
`mix playwright_ex.install -- chromium --with-deps`. See
[GitHub Actions](`e:playwright_ex:debugging-and-ci.md#github-actions`) for a workflow.
For annotations of failed tests, run the first `mix test` with
`--formatter ExUnit.CLIFormatter --formatter PlaywrightEx.Test.GitHubFormatter` (see
`PlaywrightEx.Test.GitHubFormatter`), listing every formatter you use, since `--formatter`
replaces the default list.

Configure the backend in `config/test.exs`. The browser and its driver are
`PlaywrightEx.Test`'s, as are the [timeouts](#timeouts) unless Fluffy's config overrides them:

```elixir
config :playwright_ex, :test,
  browser_name: :chromium,
  launch_options: [headless: true],
  # Traces, screenshots and videos of failed tests, under test-results/.
  trace: :retain_on_failure,
  screenshot: :only_on_failure
```

`driver: [executable: ...]` optionally points at a Playwright 1.65 CLI such as
`node_modules/.bin/playwright`, not `cli.js`; by default the pinned driver is used.

`launch_options` are passed to `PlaywrightEx.BrowserType.launch/2` unchanged. Set
`launch_options: [timeout: 10_000]` to limit browser launch; otherwise Playwright's
default of 3 minutes applies.

`mix playwright_ex.install --no-browsers` installs only the driver. That is enough in
Microsoft's Playwright image, `mcr.microsoft.com/playwright:v<version>-noble` with the
driver's version (`PlaywrightEx.Driver.version/0`): the driver finds the image's browsers at
`PLAYWRIGHT_BROWSERS_PATH`. For a system browser, as on Nix, also set
`launch_options: [executable_path: System.find_executable("google-chrome-stable")]` or
`channel:`.

A module that starts Playwright sessions needs `use PlaywrightEx.Test` after
`use ExUnit.Case` (or in your case template's `using`). It records every Playwright
session of the test: one `trace.zip` of all its sessions, a screenshot of each page as
its session closes, and videos, each `:off` by default, and a failed test's
`error-context.md`. The `*_on_failure` modes record every test and drop the files of
passing ones. Each test writes to its own dir under `output_dir` (`test-results`);
ignore it in git and configure CI to upload it when the test job fails. To override the
config for a module or test, tag it, such as `@tag trace: true`. See `PlaywrightEx.Test`
for the modes and file names.

As in Playwright, browser `console` messages and uncaught page errors are not
printed; the trace has them. To log them, register a listener, such as
`on(session, Event.console(), &Logger.info(PlaywrightEx.ConsoleMessage.text(&1)))`.

Set `browser_name: :firefox` or `browser_name: :webkit` after installing the
corresponding browser (`mix playwright_ex.install -- firefox`).
See [Browser baseline](capabilities.md#browser-baseline) for conformance coverage.
Fluffy creates a fresh isolated `BrowserContext` for each session, in the browser of
its `browser:` option, else in the test's browser from
`PlaywrightEx.Test.BrowserPool.browser/1`, Playwright Test's worker-scoped `browser`. The
test holds that browser until it ends, and a test that starts no Playwright session takes
none. At most `workers` tests hold one at once (`config :playwright_ex, :test`, half the
schedulers by default), others wait for one; see
[Workers](`e:playwright_ex:testing-with-exunit.md#workers`). No driver or browser starts
until a session needs one, a lost browser is launched again for the next session, and the
drivers stop after the suite. For more users in a test, start more sessions: each gets its
own browser context.

To debug one test headed or slowed down, pass it a browser with its own `launch_options:`,
merged over the config:

```elixir
browser = PlaywrightEx.Test.BrowserPool.browser(launch_options: [headless: false, slow_mo: 500])

:playwright
|> start_session(browser: browser)
|> visit("/creatures")
```

Call it in `setup_all` to cover a module; `browser_name:` and `driver:` override the same
way. Other options get a worker of their own, a driver and its browser, which counts toward
`workers` unless the test or module holds one already; at `workers`, the longest idle worker of
other options restarts its driver for them. See
[Debugging one test](`e:playwright_ex:testing-with-exunit.md#debugging-one-test`).

To run the browsers on a Playwright server, such as Playwright's Docker image, set
`connect_options: [ws_endpoint: "ws://localhost:3000/", expose_network: "<loopback>"]` in
`config :playwright_ex, :test`, or give one session
`browser: PlaywrightEx.Test.BrowserPool.browser(connect_options: [...])`. The remote browser
must reach your app, as pages, the Ecto sandbox header and the LiveView socket go to `base_url`:
`expose_network: "<loopback>"` tunnels `localhost` and `127.0.0.1` to your machine, so
`base_url` stays as it is. Otherwise `base_url` must be an address the container reaches, such as
`http://host.docker.internal:4002`, and the endpoint's `check_origin` must allow it. See
[Remote browsers](`e:playwright_ex:testing-with-exunit.md#remote-browsers`) for the options and
an env-var switch.

## Ecto sandbox

Fluffy is not a production dependency, so application code that names it must
compile only for tests. As `Phoenix.Ecto.SQL.Sandbox` recommends, enable a flag in
`config/test.exs`:

```elixir
config :my_app, sql_sandbox: true
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

The application owns the sandbox, as with `Phoenix.ConnTest`: keep the generated
DataCase setup, which starts an owner for each test and stops it in `on_exit`, and use
your `ConnCase` (or `DataCase`) before `use PlaywrightEx.Test` or `use Fluffy.Case`:

```elixir
def setup_sandbox(tags) do
  pid = Ecto.Adapters.SQL.Sandbox.start_owner!(MyApp.Repo, shared: not tags[:async])
  on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
end
```

Name the repositories once, and Fluffy adds their sandbox metadata for the test
process to every browser session's requests:

```elixir
config :fluffy, ecto_repos: [MyApp.Repo]
```

Sessions close in their own `on_exit`, registered after the DataCase's, so browser
contexts and in-process LiveViews close before the owner stops. A plain
`Ecto.Adapters.SQL.Sandbox.checkout/1` in the test process is not supported for browser
tests: its connection goes with the test process, before the browser closes.

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

Only browser requests carry the metadata. Phoenix sessions run requests in the test
process and LiveViews with it in `$callers`, as `Phoenix.ConnTest` does, so they use its
connection and mocks without an allowance.

Fluffy validates this configuration when its application starts. With the
`user-agent` header, list `:user_agent` in the socket's `connect_info` in place of
`:x_headers`. An application may instead retain its own LiveView/channel hook when
additional ownership rules require application state; use the same encoded metadata
and call `Phoenix.Ecto.SQL.Sandbox.allow/2` there.

## Upload limits

```elixir
config :fluffy, file_input_max_bytes: 10_000_000
```

`file_input_max_bytes` bounds the aggregate bytes Fluffy will snapshot for one
`Fluffy.set_input_files/3` or `Fluffy.set_input_files/4` action. It applies to local
paths and in-memory payloads on all three drivers and can be overridden with the
action's `max_bytes:` option.
