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
      assert base_url(start.(endpoint: __MODULE__.ActiveEndpoint)) == "http://127.0.0.1:43123"
      assert base_url(start.([])) == "http://hogwarts.test"
    end

    # An endpoint's is its running listener's (`ActiveEndpoint`), else its configured URL.
    test "a #{backend} session's base URL defaults to the configured endpoint's" do
      Application.put_env(:fluffy, :endpoint, __MODULE__.InactiveEndpoint)

      assert base_url(start_session(unquote(backend))) == "http://configured.example:4002"
    end
  end

  @tag Playwright.Test.use(base_url: "http://hogwarts.test")
  test "a test's base URL starts Playwright without an endpoint" do
    Application.delete_env(:fluffy, :endpoint)

    assert base_url(start_session(:playwright)) == "http://hogwarts.test"
  end

  test "missing global and session configuration reports the required setting" do
    Application.delete_env(:fluffy, :endpoint)

    assert_raise ArgumentError, ~r/missing Fluffy endpoint/, fn ->
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
      assert_raise ArgumentError, ~r/pass `#{key}:` to start_session\/2, not in `browser_context:`/, fn ->
        start_session(:playwright, browser_context: [{key, nil}])
      end
    end
  end

  defmodule WrongEndpoint do
    def url, do: "http://endpoint.invalid"
  end

  defmodule ActiveEndpoint do
    def url, do: "http://configured.example:4002/prefix"
    def server_info(:http), do: {:ok, {{127, 0, 0, 1}, 43_123}}
  end

  defmodule InactiveEndpoint do
    def url, do: "http://configured.example:4002"
    def server_info(:http), do: {:error, :not_found}
  end

  defp restore_env(key, nil), do: Application.delete_env(:fluffy, key)
  defp restore_env(key, value), do: Application.put_env(:fluffy, key, value)
end
