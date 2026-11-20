defmodule Fluffy.SessionConfigurationTest do
  use Fluffy.Support.Case, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Support.Server
  alias Fluffy.Support.Web.Endpoint

  setup do
    original_endpoint = Application.get_env(:fluffy, :endpoint)
    on_exit(fn -> restore_env(:endpoint, original_endpoint) end)

    :ok
  end

  test "the configured endpoint supplies Phoenix endpoint and base URL defaults" do
    Application.put_env(:fluffy, :endpoint, Endpoint)

    session = start_session(:phoenix)

    assert Fluffy.Session.context(session).http.endpoint == Endpoint
    assert base_url(session) == Endpoint.url()

    session
    |> visit("/chamber")
    |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
  end

  test "a session's endpoint: overrides the configured one" do
    Application.put_env(:fluffy, :endpoint, __MODULE__.WrongEndpoint)

    :phoenix
    |> start_session(endpoint: Endpoint)
    |> visit("/chamber")
    |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
  end

  # As Playwright's `baseURL`, from the most specific level: the session's `base_url:`, else its
  # `endpoint:`'s, else the test's, else the configured endpoint's.
  for backend <- [:phoenix, :playwright] do
    @tag Playwright.Test.use(base_url: "http://hogwarts.test")
    test "a #{backend} session's base URL is the most specific one" do
      Application.put_env(:fluffy, :endpoint, __MODULE__.WrongEndpoint)
      start = &start_session(unquote(backend), &1)

      assert base_url(start.(endpoint: __MODULE__.ActiveEndpoint, base_url: Server.base_url())) == Server.base_url()
      assert base_url(start.(endpoint: __MODULE__.ActiveEndpoint)) == "http://configured.example:43123"
      assert base_url(start.([])) == "http://hogwarts.test"
    end

    # An endpoint's is its `url` config's, on its running listener's port (`ActiveEndpoint`).
    test "a #{backend} session's base URL defaults to the configured endpoint's" do
      Application.put_env(:fluffy, :endpoint, __MODULE__.InactiveEndpoint)

      assert base_url(start_session(unquote(backend))) == "http://configured.example:4002"
    end
  end

  # Whatever the `url` scheme: a test's HTTPS listener often has a self-signed certificate.
  test "the base URL takes the HTTP listener's scheme and port before the HTTPS one's" do
    assert base_url(start_session(:phoenix, endpoint: __MODULE__.BothEndpoint)) == "http://configured.example:43123"
  end

  # phx.new's shape: the listener on 127.0.0.1, the url host `localhost` and the default
  # `check_origin`, which compares the browser's origin with the url host.
  describe "an endpoint whose url host is not its listener's address" do
    setup context do
      # `port: 0` by default; `@tag :fixed_port` is phx.new's shape, the url port the listener's.
      port = if context[:fixed_port], do: Server.lease_port(), else: 0
      url_port = if context[:fixed_port], do: [port: port], else: []

      config = [
        adapter: Bandit.PhoenixAdapter,
        http: [ip: {127, 0, 0, 1}, port: port],
        url: [host: "localhost"] ++ url_port,
        live_view: [signing_salt: "fluffy-live-view"],
        pubsub_server: Fluffy.TestPubSub,
        secret_key_base: String.duplicate("fluffy-secret-", 8),
        server: true
      ]

      Application.put_env(:fluffy, __MODULE__.LocalhostEndpoint, config)
      on_exit(fn -> Application.delete_env(:fluffy, __MODULE__.LocalhostEndpoint) end)
      start_supervised!(__MODULE__.LocalhostEndpoint)
      {:ok, {_address, port}} = __MODULE__.LocalhostEndpoint.server_info(:http)

      %{url: "http://localhost:#{port}"}
    end

    for backend <- [:phoenix, :playwright] do
      test "a #{backend} session's base URL takes the url host and the listener's port", %{url: url} do
        assert base_url(start_session(unquote(backend), endpoint: __MODULE__.LocalhostEndpoint)) == url
      end
    end

    # With `port: 0` the endpoint's `url()` has port 0, another origin than the base URL's.
    @tag :fixed_port
    test "a Phoenix session visits the app's own absolute URL", %{url: url} do
      assert __MODULE__.LocalhostEndpoint.url() == url

      :phoenix
      |> start_session(endpoint: __MODULE__.LocalhostEndpoint)
      |> visit(__MODULE__.LocalhostEndpoint.url() <> "/chamber")
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    test "a browser's LiveView connects past check_origin" do
      :playwright
      |> start_session(endpoint: __MODULE__.LocalhostEndpoint)
      |> visit("/live/three-heads")
      |> click(by_role(:button, name: "Play the flute"))
      |> expect("Sleeping heads: 1" |> by_text() |> to_be_visible())
    end
  end

  @tag Playwright.Test.use(base_url: "http://hogwarts.test")
  test "a test's base URL starts Playwright without an endpoint" do
    Application.delete_env(:fluffy, :endpoint)

    assert base_url(start_session(:playwright)) == "http://hogwarts.test"
  end

  test "missing global and session configuration reports the required setting" do
    Application.delete_env(:fluffy, :endpoint)

    assert_raise ArgumentError, ~r/^Fluffy.start_session\/2: missing Fluffy endpoint/, fn ->
      start_session(:phoenix)
    end

    assert_raise ArgumentError, ~r/missing Fluffy base URL/, fn ->
      start_session(:playwright)
    end
  end

  test "rejects unknown common session options" do
    assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:mystery/, fn ->
      start_session(:phoenix, endpoint: Endpoint, mystery: true)
    end
  end

  # As in Playwright Test, there is no per-session timeout.
  test "rejects a session timeout:" do
    for backend <- [:phoenix, :playwright] do
      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:timeout/, fn ->
        start_session(backend, endpoint: Endpoint, timeout: 1_000)
      end
    end
  end

  # One place each, the same on both backends: not in Playwright's context options.
  test "rejects base_url and extra_http_headers in browser_context:" do
    for key <- [:base_url, :extra_http_headers] do
      assert_raise ArgumentError,
                   ~r/^Fluffy.start_session\/2: pass #{inspect(key)} as its own option, not in :browser_context/,
                   fn ->
                     start_session(:playwright, browser_context: [{key, nil}])
                   end
    end
  end

  defmodule WrongEndpoint do
    def struct_url, do: URI.parse("http://endpoint.invalid")
  end

  defmodule ActiveEndpoint do
    def struct_url, do: URI.parse("http://configured.example:4002")
    def server_info(:http), do: {:ok, {{127, 0, 0, 1}, 43_123}}
  end

  defmodule BothEndpoint do
    def struct_url, do: URI.parse("https://configured.example")
    def server_info(:http), do: {:ok, {{127, 0, 0, 1}, 43_123}}
    def server_info(:https), do: {:ok, {{127, 0, 0, 1}, 43_443}}
  end

  defmodule InactiveEndpoint do
    def struct_url, do: URI.parse("http://configured.example:4002")
    def server_info(:http), do: {:error, :not_found}
  end

  defmodule LocalhostEndpoint do
    use Phoenix.Endpoint, otp_app: :fluffy

    @session_options [store: :cookie, key: "_fluffy_test", signing_salt: "fluffy-session", same_site: "Lax"]

    socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]], longpoll: false)
    plug(Plug.Static, at: "/", from: {:fluffy, "priv/static"}, gzip: false, only: ~w(assets))
    plug(Plug.Session, @session_options)
    plug(Fluffy.Support.Web.Router)
  end

  defp restore_env(key, nil), do: Application.delete_env(:fluffy, key)
  defp restore_env(key, value), do: Application.put_env(:fluffy, key, value)
end
