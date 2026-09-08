defmodule Fluffy.HTTPFixtureRegistryTest do
  use Fluffy.TestCase, async: true

  alias Fluffy.TestHTTPFixtures

  test "registrations have collision-free paths and capture the request contract" do
    first = TestHTTPFixtures.register(%{body: "first"})
    second = TestHTTPFixtures.register(%{body: "second"})

    refute first.token == second.token
    refute first.path == second.path

    response = http_request(:get, TestHTTPFixtures.url(first, "/orders?state=open"))

    assert response.status == 200
    assert response.body == "first"

    assert [request] = TestHTTPFixtures.requests(first)
    assert request.method == "GET"
    assert request.path == "/orders"
    assert request.query == "state=open"
    assert request.body == ""
  end

  test "a declarative response sequence is consumed in registration order" do
    fixture =
      TestHTTPFixtures.register_sequence([
        %{status: 302, headers: [{"location", "next"}]},
        %{body: "destination"}
      ])

    first = http_request(:get, TestHTTPFixtures.url(fixture))
    second = http_request(:get, TestHTTPFixtures.url(fixture, "/next"))

    assert first.status == 302
    assert first.headers["location"] == "next"
    assert second.status == 200
    assert second.body == "destination"
  end

  test "a response function can derive a response from the captured request" do
    fixture =
      TestHTTPFixtures.register(fn request ->
        %{body: "#{request.method} #{request.path}?#{request.query} #{request.body}"}
      end)

    response =
      http_request(
        :post,
        TestHTTPFixtures.url(fixture, "/submit?source=test"),
        [{"content-type", "application/x-www-form-urlencoded"}],
        "first=one&second=two"
      )

    assert response.body == "POST /submit?source=test first=one&second=two"
  end

  test "registrations are removed when their owner exits" do
    parent = self()

    {owner, monitor} =
      spawn_monitor(fn ->
        fixture = TestHTTPFixtures.register(%{body: "temporary"})
        send(parent, {:fixture, fixture})
      end)

    assert_receive {:fixture, fixture}
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}

    refute TestHTTPFixtures.registered?(fixture)
    assert http_request(:get, TestHTTPFixtures.url(fixture)).status == 404
  end

  defp http_request(method, url, headers \\ [], body \\ "") do
    request =
      case method do
        :get -> {String.to_charlist(url), charlist_headers(headers)}
        :post -> {String.to_charlist(url), charlist_headers(headers), ~c"text/plain", body}
      end

    {:ok, {{_version, status, _reason}, response_headers, response_body}} =
      :httpc.request(method, request, [autoredirect: false], body_format: :binary)

    %{
      status: status,
      headers:
        Map.new(response_headers, fn {name, value} ->
          {name |> to_string() |> String.downcase(), to_string(value)}
        end),
      body: response_body
    }
  end

  defp charlist_headers(headers) do
    Enum.map(headers, fn {name, value} ->
      {String.to_charlist(name), String.to_charlist(value)}
    end)
  end
end
