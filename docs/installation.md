# Installation and runtime

## Elixir dependency

```elixir
defp deps do
  [
    {:fluffy, "~> 0.2.0", only: :test}
  ]
end
```

## JavaScript and browser

The browser process uses the JavaScript Playwright package installed by the
consumer application. The initial pinned contract is Playwright 1.63.0:

```bash
pnpm add --save-dev playwright@1.63.0
pnpm exec playwright install chromium
```

Configure its CLI path in `config/test.exs`:

```elixir
config :fluffy,
  file_input_max_bytes: 10_000_000,
  playwright: [
    enabled: true,
    engine: :chromium,
    executable: Path.expand("../node_modules/playwright/cli.js", __DIR__),
    timeout: 15_000,
    launch_options: [headless: true],
    artifact_dir: System.get_env("FLUFFY_ARTIFACT_DIR"),
    trace_dir: System.get_env("FLUFFY_TRACE_DIR", "traces"),
    js_logger: Fluffy.Playwright.ConsoleLogger
  ]
```

`file_input_max_bytes` bounds the aggregate bytes Fluffy will snapshot for
one `set_input_files/3,4` action. It applies to local paths and in-memory
payloads on all three drivers and can be overridden with the action's
`max_bytes:` option. Fluffy checks path metadata before reading file bytes
and checks the actual snapshot again afterward.

Setting `artifact_dir` is recommended for every project that runs Playwright
tests. Fluffy writes HTML, a full-page screenshot, and the formatted error
there when a public browser operation fails. Use a writable per-run directory
locally and configure CI to upload it when the test job fails; artifact capture
does not run for successful operations.

The default console logger sends browser `console` messages and uncaught page
errors through Elixir's `Logger`; set `js_logger: false` to disable it or
configure another module implementing `PlaywrightEx.JsLogger`. Trace files are
created only when a test calls `Fluffy.Playwright.trace/1,2`.

Use `:firefox` or `:webkit` only after installing the corresponding browser.
Playwright provides cross-engine compatibility; Fluffy uses pinned Chromium
as its browser-backed conformance baseline.
Fluffy launches one browser lazily per configured runtime lane and creates a
fresh isolated `BrowserContext` for each session. ExUnit `max_cases` is the
default concurrency bound; Fluffy does not add a second pool limiter.
Lower it when browser startup or the host becomes resource-constrained.

## Phoenix endpoint

Configure your application endpoint once in `config/test.exs`. Fluffy uses
it for in-process requests and derives the default session URL from the
endpoint. When the endpoint has an active HTTP or HTTPS listener, its actual
bind address and port are authoritative. Fluffy falls back to
`MyAppWeb.Endpoint.url()` when no listener is running. This supports endpoints
configured with `port: 0`:

```elixir
config :fluffy, endpoint: MyAppWeb.Endpoint

config :my_app, MyAppWeb.Endpoint, server: true
```

The server is required for Playwright tests. If Playwright targets an
application hosted elsewhere, configure `config :fluffy, base_url: "..."`
instead. Explicit `endpoint:` and `base_url:` session options override the
global values for multi-endpoint or dynamic-server tests.

The application's normal browser bundle must connect its LiveSocket. A
Playwright visit containing a LiveView root waits for `phx-connected` before it
returns.

## Ecto sandbox

Add the standard Phoenix Ecto sandbox plug before the rest of the endpoint and
expose request headers to the LiveView socket:

```elixir
plug Phoenix.Ecto.SQL.Sandbox,
  header: Fluffy.Sandbox.header(),
  sandbox: Fluffy.Sandbox.allowance()

socket "/live", Phoenix.LiveView.Socket,
  websocket: [
    connect_info: [Fluffy.Sandbox.connect_info(), session: @session_options]
  ]
```

Add the Fluffy mount hook before application hooks:

```elixir
live_session :test, on_mount: Fluffy.Sandbox do
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
owners, including when the owner test process fails.

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

The sandbox value may be a module implementing `allow(repo, owner, child)` or
Phoenix Ecto's `{module, function, extra_arguments}` form. For example:

```elixir
defmodule MyApp.TestSandbox do
  def allow(repo, owner, child) do
    :ok = Ecto.Adapters.SQL.Sandbox.allow(repo, owner, child)
    MyApp.Mocks.allow(owner, child)
  end
end
```

Fluffy validates this configuration when its application starts. The same
header and allowance value must be passed to the endpoint plug, and
`connect_info/0` selects `:user_agent` or `:x_headers` for the socket. An
application may instead retain its own LiveView/channel hook when additional
ownership rules require application state; use the same encoded metadata and
call `Phoenix.Ecto.SQL.Sandbox.allow/2` there.
