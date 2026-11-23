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
+    {:fluffy, "~> 0.9.0-rc.5", only: [:dev, :test]}
   ]
 end
```

Prefer `only: [:dev, :test]` to `only: :test`: Playwright's Mix tasks, and
[`mix usage_rules.sync`](https://hexdocs.pm/usage_rules) for Fluffy's usage rules, then work
in `:dev`, where Fluffy needs no config and starts no Playwright driver or browser. Mix requires a
dependency you list to cover every environment Fluffy needs it in, so widen the
`lazy_html` line `phx.new` generates, if your app has it.
Playwright comes with Fluffy in the same environments, so `mix playwright.install`
works without listing it. List it anyway if you use
[usage rules](#usage-rules-for-coding-agents), as `usage_rules.sync` reads only the
dependencies `mix.exs` lists:
`{:playwright, ">= 0.0.0", hex: :playwright_ex, only: [:dev, :test]}`, as Fluffy's own requirement
picks the version. The app is
`:playwright` and the Hex package `playwright_ex`; `hex: :playwright_ex` is required, since
`playwright` on Hex is another library.

## Usage rules for coding agents

Fluffy ships usage rules for coding agents that build on Playwright's. Sync them with
[`usage_rules`](https://hexdocs.pm/usage_rules) as one skill, and move `phoenix:liveview`
into a skill too: Fluffy's rules override its "LiveView tests" rules, so those shouldn't sit
in an always-loaded `AGENTS.md`. Run `mix usage_rules.sync` after upgrading.

```elixir
# mix.exs
def project do
  [
    # ...
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
  ]
end
```

## Phoenix endpoint

Configure your application endpoint once in `config/test.exs`. Fluffy uses
it for in-process requests and derives the default session URL from the
endpoint: its `url` host, on the scheme and port of its HTTP listener, else its HTTPS one,
else the `url` config's. So `port: 0` works, and the host is the one Phoenix's default
`check_origin` allows. Phoenix sessions treat the app's own absolute URLs
(`MyAppWeb.Endpoint.url()`) as same-origin when the `url` port is the listener's, as with
`phx.new`'s fixed test port, not with `port: 0`:

```elixir
config :fluffy, endpoint: MyAppWeb.Endpoint

config :my_app, MyAppWeb.Endpoint, server: true
```

The server is required for Playwright tests. With `phx.new`'s defaults the browser opens
`http://localhost:4002`, which reaches the listener on `127.0.0.1`. If Playwright
targets an application hosted elsewhere, set Playwright's `base_url` instead; for
multi-endpoint or dynamic-server tests, pass a session `endpoint:` or `base_url:`
([Configuration](#configuration)).

The application's normal browser bundle must connect its LiveSocket. See
[Actionability checks and waiting](actions.md#actionability-checks-and-waiting)
for Fluffy's automatic LiveView connection wait.

## Configuration

Fluffy is Playwright Test plus Phoenix: Playwright Test owns the test's options, and Fluffy
has a key only where Playwright has no concept.

| Owner | Where, later wins | Keys |
| --- | --- | --- |
| Playwright Test | `config :playwright, :test` < project < module (`use Playwright.Test, ...` or `@moduletag Playwright.Test.use(...)`) < describe or test (`@tag Playwright.Test.use(...)`) | context options such as `base_url`, `extra_http_headers` and `locale`, `action_timeout`, `navigation_timeout`, `trace`, `screenshot`, `video`; up to the module only: the browser (`browser_name`, `launch_options`, `connect_options`); suite-wide only: `test_id_attribute` and the expect timeout, `expect: [timeout: ...]` |
| Fluffy | `config :fluffy` | `endpoint`, `ecto_repos`, `file_input_max_bytes`, `phoenix_backend_timeout` |

What applies to each kind of session:

| Setting | Phoenix session | Browser session |
| --- | --- | --- |
| `base_url`, `extra_http_headers` | yes | yes |
| `locale`, `user_agent` | as the `Accept-Language` and `User-Agent` headers a browser sends | yes |
| `test_id_attribute`, from `config :playwright, :test` only | yes | yes |
| Other context options (`viewport`, `color_scheme`, ...) | no: nothing a server sees | yes |
| Default timeouts | `phoenix_backend_timeout` (1 s) | Playwright's `action_timeout`, `navigation_timeout` and `expect: [timeout: ...]` |
| Recording: trace, screenshot, video | no (steps are recorded) | yes |
| A call's `timeout:` | overrides the default | overrides the default |

So a `Playwright.Test.use(action_timeout: ...)` tag does nothing for a Phoenix session.
Per-test values through tags or projects assume one kind of session per test.

A session's URL is, from the most specific: its `base_url:`, else its `endpoint:`'s, else
Playwright's resolved `base_url`, else the configured endpoint's. A typical Phoenix app sets
no `base_url`: Fluffy takes the endpoint's `url` host on its running listener's port, so
`port: 0`, a `PORT` variable or any other dynamic port works
([Phoenix endpoint](#phoenix-endpoint)). Set
`config :playwright, :test, base_url:` only when the browser reaches the app at another
address, as from Docker, a remote browser or a proxy; with a dynamic port, set it in
`config/runtime.exs` inside `if config_env() == :test`. A static `base_url` beats the
endpoint's URL, so it breaks a dynamic port.

- **Levels replace, they don't merge.** As in Playwright, a later level replaces an option's
  whole value, so a tag's `extra_http_headers` replaces the config's map, as does a session's
  `start_session(..., extra_http_headers: ...)` on either backend: repeat the headers you keep.
- **Language on both backends.** Set `locale` (Playwright's default is `en-US`): a Phoenix
  session sends it as `Accept-Language`, as a browser does. An `accept-language` in
  `extra_http_headers` overrides it, as in a browser.
- **Case templates.** Put `use Playwright.Test, unquote(opts)` in the template's `using`
  ([Shared test case](usage.md#shared-test-case)).
- **Logging in.** Add the session cookie your app signs, on both backends
  ([Logging in](usage.md#logging-in)).

```elixir
# config/test.exs: no base_url, as the endpoint gives it.
config :my_app, MyAppWeb.Endpoint, server: true
config :fluffy, endpoint: MyAppWeb.Endpoint, ecto_repos: [MyApp.Repo]

config :playwright, :test,
  browser_name: :chromium,
  action_timeout: 15_000,
  navigation_timeout: 15_000,
  expect: [timeout: 5_000]
```

```elixir
defmodule MyAppWeb.OwleryTest do
  use MyAppWeb.ConnCase, async: true
  use Playwright.Test

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  # Waits at most `phoenix_backend_timeout` for the button and the text.
  test "sends an owl" do
    :phoenix
    |> start_session()
    |> visit("/owlery")
    |> click(by_role(:button, name: "Send owl"))
    |> expect("Hedwig is on her way" |> by_text() |> to_be_visible())
  end

  # Playwright's timeouts and context options, overridden for this test.
  @tag Playwright.Test.use(action_timeout: 30_000, locale: "en-GB")
  test "sends an owl in a browser" do
    :playwright
    |> start_session()
    |> visit("/owlery")
    |> click(by_role(:button, name: "Send owl"))
    |> expect("Hedwig is on her way" |> by_text() |> to_be_visible())
  end
end
```

### Timeouts

A browser session's defaults are Playwright Test's. Without an action or navigation timeout,
the test's timeout bounds them (ExUnit's default is 60 seconds, against Playwright Test's 30, so
for faster failures set both, as Fluffy's own suite does with 15 seconds, or lower ExUnit's
`timeout:`). Playwright.Test then closes the test's contexts just before, so a call that hangs
fails with "Test timeout of 60000ms exceeded." and its call log. It sets the timeouts on the
test's browser contexts, so native calls in an `unwrap` callback get them too.

A Phoenix session's action retries, assertions and event waits default to
`config :fluffy, phoenix_backend_timeout:`, 1 second: an in-process session answers at once,
so a long wait is only for something that isn't there. Its `0` checks once, and `:infinity`
waits until the test's timeout, which then fails the operation with Fluffy's error and the same
reason. There is no per-session timeout on either backend; pass `timeout:` to a call.

A value means what its source says: Playwright's `0` is no limit, so write `:infinity`, which
reads the same in both configs. An operation's `timeout: 0` checks once, unlike Playwright.
Playwright assertions check once too, but Playwright actions and waits reject `0` with an
`ArgumentError`, as they cannot check once; pass a positive timeout. So do screenshot
assertions, which take each screenshot within the timeout.

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

Only the Playwright backend needs a browser. The `:playwright` dependency pins its
driver, the Playwright CLI that runs the browsers (not one of Fluffy's drivers); install it
and a browser with:

```bash
mix playwright.install chromium
```

On Linux CI runners, add `--with-deps` to install the browser's system packages too:
`mix playwright.install chromium --with-deps`. See
[GitHub Actions](`e:playwright:debugging-and-ci.md#github-actions`) for a workflow.
For annotations of failed tests, run the first `mix test` with
`--formatter ExUnit.CLIFormatter --formatter Playwright.Test.GitHubFormatter` (see
`Playwright.Test.GitHubFormatter`), listing every formatter you use, since `--formatter`
replaces the default list.

Configure the backend in `config/test.exs`. The browser and its driver are
`Playwright.Test`'s, as are its [timeouts](#timeouts):

```elixir
config :playwright, :test,
  browser_name: :chromium,
  headless: true,
  # Traces, screenshots and videos of failed tests, under test-results/.
  trace: :retain_on_failure,
  screenshot: :only_on_failure
```

`config :playwright, :driver, executable: ...` optionally points at a Playwright 1.65 CLI such
as `node_modules/.bin/playwright`, not `cli.js`; by default the pinned driver is used. Put it in
`config/config.exs`, which `mix playwright.install` reads in `:dev`.

`launch_options` are passed to `Playwright.BrowserType.launch/2` unchanged. Set
`launch_options: [timeout: 10_000]` to limit browser launch; otherwise Playwright's
default of 3 minutes applies.

`mix playwright.install --no-browsers` installs only the driver. That is enough in
Microsoft's Playwright image, `mcr.microsoft.com/playwright:v<version>-noble` with the
driver's version (`Playwright.Driver.version/0`): the driver finds the image's browsers at
`PLAYWRIGHT_BROWSERS_PATH`. For a system browser, as on Nix, also set
`launch_options: [executable_path: System.find_executable("google-chrome-stable")]` or
`channel:`.

Test modules have `use Playwright.Test` after your `ConnCase` or `use ExUnit.Case` (or in
your case template's `using`): every session needs it. It records every Playwright session of the test: one `trace.zip` of all its
sessions, a screenshot of each page as its session closes, and videos, each `:off` by
default, and a failed test's `error-context.md`. The `*_on_failure` modes record every
test and drop the files of passing ones. Each test writes to its own dir under `output_dir` (`test-results`);
ignore it in git and configure CI to upload it when the test job fails. To override the
config for a module, pass the mode to `use Playwright.Test, trace: :on`, or tag a describe
block or test, such as `@tag Playwright.Test.use(trace: :on)`. See `Playwright.Test` for the
modes and file names.

As in Playwright, browser `console` messages and uncaught page errors are not
printed; the trace has them. To log them, register a listener, such as
`on(session, Event.console(), &Logger.info(Playwright.ConsoleMessage.text(&1)))`.

Set `browser_name: :firefox` or `browser_name: :webkit` after installing the
corresponding browser (`mix playwright.install firefox`).
See [Browser baseline](capabilities.md#browser-baseline) for conformance coverage.
Fluffy creates a fresh isolated `BrowserContext` for each session, in the browser of
its `browser:` option, else in the test's browser from
`Playwright.Test.BrowserPool.browser/1`, Playwright Test's worker-scoped `browser`. The
test holds that browser until it ends, and a test that starts no Playwright session takes
none. At most `workers` tests hold one at once (`config :playwright, :test`, half the
schedulers by default), others wait for one; see
[Workers](`e:playwright:test-artifacts.md#workers`). No driver or browser starts
until a session needs one, a lost browser is launched again for the next session, and the
drivers stop after the suite. For more users in a test, start more sessions: each gets its
own browser context.

To debug one test headed or slowed down, pass it a browser with its own `headless:` or
`launch_options:`, merged one key at a time over the module's, else the config's:

```elixir
browser = Playwright.Test.BrowserPool.browser(headless: false, launch_options: [slow_mo: 500])

:playwright
|> start_session(browser: browser)
|> visit("/creatures")
```

`browser_name:` and `channel:` override the same way. Other options get a worker of their own, a
driver and its browser, which counts toward `workers` unless the test or module holds one
already; at `workers`, the longest idle worker of other options restarts its driver for them.
For a whole module, set `use Playwright.Test, headless: false, launch_options: [slow_mo: 500]`
or `@moduletag Playwright.Test.use(headless: false)`; a module's `launch_options` replace the
config's. Its sessions then get that browser without `browser:`. See
[Debugging one test](`e:playwright:test-artifacts.md#debugging-one-test`).

To run the browsers on a Playwright server, such as Playwright's Docker image, set
`connect_options: [ws_endpoint: "ws://localhost:3000/", expose_network: "<loopback>"]` in
`config :playwright, :test`, or give one session
`browser: Playwright.Test.BrowserPool.browser(connect_options: [...])`. The remote browser
must reach your app, as pages, the Ecto sandbox header and the LiveView socket go to `base_url`:
`expose_network: "<loopback>"` tunnels `localhost` and `127.0.0.1` to your machine, so
`base_url` stays as it is. Otherwise `base_url` must be an address the container reaches, such as
`http://host.docker.internal:4002`, and the endpoint's `check_origin` must allow it. See
[Remote browsers](`e:playwright:test-artifacts.md#remote-browsers`) for the options and
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
your `ConnCase` (or `DataCase`) before `use Playwright.Test`:

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
contexts and in-process LiveViews close before the owner stops. Start sessions in the test
process or its `setup`: a Phoenix session started from a `Task` belongs to the test too, but
closes when the test process exits, alongside the `on_exit` callbacks, so maybe after the
owner stops. A plain `Ecto.Adapters.SQL.Sandbox.checkout/1` in the test process is not
supported for browser tests: its connection goes with the test process, before the browser
closes.

A LiveView's process exits shortly after its browser closes, so the test waits, up to 5 seconds,
for the LiveViews its browser sessions connected to exit before the owner stops: their
`terminate/2` can still use the database. This covers sessions started in the test process or its
`setup`, not from a Task.

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
and call `Phoenix.Ecto.SQL.Sandbox.allow(metadata, Fluffy.Sandbox)` there, which also gives it
the wait for LiveViews to exit. `Fluffy.Sandbox` grants the configured `:sandbox`, so a hook
that passed its own allowance module moves that module to `sandbox:` above.

## Upload limits

```elixir
config :fluffy, file_input_max_bytes: 10_000_000
```

`file_input_max_bytes` bounds the aggregate bytes Fluffy will snapshot for one
`Fluffy.set_input_files/3` or `Fluffy.set_input_files/4` action. It applies to local
paths and in-memory payloads on all three drivers and can be overridden with the
action's `max_bytes:` option.
