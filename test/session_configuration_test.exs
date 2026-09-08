defmodule Fluffy.SessionConfigurationTest do
  use Fluffy.TestCase, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestWeb.Endpoint

  setup do
    original_endpoint = Application.get_env(:fluffy, :endpoint)
    original_base_url = Application.get_env(:fluffy, :base_url)

    on_exit(fn ->
      restore_env(:endpoint, original_endpoint)
      restore_env(:base_url, original_base_url)
    end)

    :ok
  end

  test "the configured endpoint supplies Phoenix endpoint and base URL defaults" do
    Application.put_env(:fluffy, :endpoint, Endpoint)
    Application.delete_env(:fluffy, :base_url)

    session = start_session(:phoenix)

    assert session.context.http.endpoint == Endpoint
    assert session.context.http.base_url == Endpoint.url()

    session
    |> visit("/chamber")
    |> expect(visible(by_text("The guardian sleeps")))
  end

  test "an active endpoint listener supplies the default base URL port" do
    Application.put_env(:fluffy, :endpoint, __MODULE__.ActiveEndpoint)
    Application.delete_env(:fluffy, :base_url)

    session = start_session(:phoenix)

    assert session.context.http.base_url == "http://127.0.0.1:43123"
  end

  test "an unavailable endpoint listener falls back to the configured endpoint URL" do
    Application.put_env(:fluffy, :endpoint, __MODULE__.InactiveEndpoint)
    Application.delete_env(:fluffy, :base_url)

    session = start_session(:phoenix)

    assert session.context.http.base_url == "http://configured.example:4002"
  end

  test "session options override global endpoint and base URL" do
    Application.put_env(:fluffy, :endpoint, __MODULE__.WrongEndpoint)
    Application.put_env(:fluffy, :base_url, "http://global.invalid")

    session =
      start_session(:phoenix,
        endpoint: Endpoint,
        base_url: Fluffy.TestServer.base_url()
      )

    session
    |> visit("/chamber")
    |> expect(visible(by_text("The guardian sleeps")))
  end

  test "a configured base URL overrides the endpoint URL" do
    Application.put_env(:fluffy, :endpoint, Endpoint)
    Application.put_env(:fluffy, :base_url, "http://configured.example")

    session = start_session(:phoenix)

    assert session.context.http.base_url == "http://configured.example"
  end

  test "a configured base URL starts Playwright without an endpoint" do
    Application.delete_env(:fluffy, :endpoint)
    Application.put_env(:fluffy, :base_url, Fluffy.TestServer.base_url())

    session = start_session(:playwright)

    assert session.context.base_url == Fluffy.TestServer.base_url()
  end

  test "missing global and session configuration reports the required setting" do
    Application.delete_env(:fluffy, :endpoint)
    Application.delete_env(:fluffy, :base_url)

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
