# Installation and runtime

Add Fluffy and configure your Phoenix endpoint first. Complete Playwright setup
if you need browser tests, and Ecto sandbox setup if your application uses a
database. Then follow [Usage](usage.md) for your first test and shared test case.

## Elixir dependency

```elixir
defp deps do
  [
    {:fluffy, "~> 0.9.0-rc.1", only: :test}
  ]
end
```

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
match, so `check_origin: false` lets the LiveView socket connect. If Playwright
targets an application hosted elsewhere, configure
`config :fluffy, base_url: "..."` instead. Explicit `endpoint:` and `base_url:`
session options override the global values for multi-endpoint or dynamic-server
tests.

The application's normal browser bundle must connect its LiveSocket. See
[Actionability checks and waiting](actions.md#actionability-checks-and-waiting)
for Fluffy's automatic LiveView connection wait.

## Timeouts

Phoenix sessions wait up to 1 second by default. Set `config :fluffy, timeout: 2_000`
to change that, or pass `timeout:` to `Fluffy.start_session/2` for one session. Playwright
sessions ignore it and use the `timeout` under `config :fluffy, playwright:` (default
`15_000`), also overridden by `Fluffy.start_session/2`.

An operation's `timeout: 0` checks once, unlike Playwright, where `0` disables the timeout.
Playwright assertions check once too, but Playwright actions and waits reject 0 with an
`ArgumentError`, as they cannot check once; pass a positive timeout.

For no timeout, pass `timeout: :infinity`, never Playwright's `0`. Playwright then waits
with no timeout, and LiveView retries and event waits go on until the test times out; Static
checks once, as with any timeout, since nothing on its page changes.

A Playwright timeout under a second limits the operation only. Fluffy's own reads of the page
around it still get a full second, so a page whose main thread is blocked takes a second to
report, not the shorter timeout.

As in Playwright, calls that have no timeout there have none in Fluffy and take no
`timeout:`: page `evaluate`, `content` and `title`, page-wide keyboard and mouse input,
clock calls, context setters, closing a page, `unroute_all`, and reading a download or a
response body. On a blocked page they wait until the test times out (ExUnit's default
is 60 seconds).

## Playwright setup

Only the Playwright backend needs a browser. PlaywrightEx pins its Playwright
driver; install it and a browser with:

```bash
MIX_ENV=test mix playwright_ex.install -- chromium
```

The task needs `MIX_ENV=test` because PlaywrightEx comes in only through the test-only `:fluffy` dependency.

Configure the backend in `config/test.exs`:

```elixir
config :fluffy,
  playwright: [
    enabled: true,
    engine: :chromium,
    timeout: 15_000,
    launch_options: [headless: true],
    pool_size: 1,
    artifact_dir: System.get_env("FLUFFY_ARTIFACT_DIR"),
    trace_dir: System.get_env("FLUFFY_TRACE_DIR", "traces")
  ]
```

`executable` optionally points at another Playwright 1.65 driver; by default the
pinned driver is used.

`launch_options` are passed to `PlaywrightEx.BrowserType.launch/2` unchanged. Set
`launch_options: [timeout: 10_000]` to limit browser launch; otherwise Playwright's
default of 3 minutes applies. To use a system browser, set
`launch_options: [executable_path: System.find_executable("google-chrome-stable")]`.
`MIX_ENV=test mix playwright_ex.install --no-browsers` installs only the driver for an existing browser.

Setting `artifact_dir` is recommended for every project that runs Playwright
tests. Fluffy writes HTML, a full-page screenshot, and the formatted error
there when a public browser operation fails. Use a writable per-run directory
locally and configure CI to upload it when the test job fails; artifact capture
does not run for successful operations.

As in Playwright, browser `console` messages and uncaught page errors are not
printed; set `log_browser_console: true` to send them to Elixir's `Logger`. Trace files are created only when a test
calls `Fluffy.Playwright.trace/1` or `Fluffy.Playwright.trace/2`.

Set `engine: :firefox` or `engine: :webkit` after installing the corresponding
browser (`MIX_ENV=test mix playwright_ex.install -- firefox`).
See [Browser baseline](capabilities.md#browser-baseline) for conformance coverage.
Fluffy creates a fresh isolated `BrowserContext` for each session, in a pool of
`pool_size` browsers (default `1`). No driver or browser starts until a session
needs one. Sessions go to the least-loaded browser, ties to the lowest slot, so
sequential sessions reuse one browser and only concurrent sessions launch more.
A lost browser is launched again for the next session that needs it, and the
others keep running. ExUnit `max_cases` remains the concurrency bound; lower it
when browser startup or the host becomes resource-constrained. Firefox dispatches
input for all of a browser's pages in one queue and times out under load, so set
`pool_size` to about half the logical cores for Firefox suites.

## Ecto sandbox

Fluffy is a test-only dependency, so application code that names it must compile
only for tests. As `Phoenix.Ecto.SQL.Sandbox` recommends, enable a flag in
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

Name the application's repositories once, then establish one scope in every
Fluffy test through the same callback used by applications without Ecto:

```elixir
config :fluffy, ecto_repos: [MyApp.Repo]
```

```elixir
setup context do
  Fluffy.Test.setup(context)
end
```

The scope adopts an existing DataCase/ConnCase checkout when present. It
closes browser contexts and in-process LiveViews before stopping sandbox
owners, including when the owner test process fails. Sessions also close when
their owning process exits. Call setup once per test, whether or not Ecto is used.

Use `Fluffy.Test.setup(context, sandbox: false)` for a test that deliberately
needs lifecycle management without the configured repositories, or pass
`repos: [...]` to override them in an umbrella or multi-repository test.

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
