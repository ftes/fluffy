defmodule Fluffy.Conformance.NetworkEventTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Locator

  alias Fluffy.Event
  alias Fluffy.HTTPEvent
  alias Fluffy.Request
  alias Fluffy.Response
  alias Fluffy.TestHTTPFixtures

  @tag driver: :playwright
  test "captures a predicate-matched browser request" do
    fixture = network_fixture()
    session = start_test_session()

    session =
      session
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> wait_for(
        Event.request(
          :save_request,
          fn %HTTPEvent{url: url} -> String.ends_with?(url, "/api?source=button") end
        ),
        &click(&1, by_role(:button, name: "Save"))
      )
      |> expect(Request.to_have_method(:save_request, "POST"))
      |> expect(Request.to_have_url(:save_request, TestHTTPFixtures.url(fixture, "/api?source=button")))
      |> expect(Request.to_have_headers(:save_request, %{"x-fluffy" => "network-test"}))
      |> expect(Request.to_have_resource_type(:save_request, "fetch"))
      |> expect(Request.to_have_post_data(:save_request, "payload"))
      |> expect(Request.to_have_page(:save_request, :main))

    assert %HTTPEvent{kind: :request, status: nil} = request(session, :save_request)
  end

  @tag driver: :playwright
  test "captures a regex-matched browser response" do
    fixture = network_fixture()
    session = start_test_session()

    session =
      session
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> wait_for(
        Event.response(:save_response, ~r{/api\?source=button$}),
        &click(&1, by_role(:button, name: "Save"))
      )
      |> expect(Response.to_have_request_method(:save_response, "POST"))
      |> expect(Response.to_have_url(:save_response, TestHTTPFixtures.url(fixture, "/api?source=button")))
      |> expect(Response.to_have_headers(:save_response, %{"content-type" => "application/json"}))
      |> expect(Response.to_have_resource_type(:save_response, "fetch"))
      |> expect(Response.to_have_status(:save_response, 207))
      |> expect(Response.to_have_status_text(:save_response, "Multi-Status"))
      |> expect(Response.to_have_page(:save_response, :main))

    assert %HTTPEvent{kind: :response, status: 207} = response(session, :save_response)
  end

  test "reports browser network streams as unsupported before a Phoenix action" do
    session = Fluffy.session_for_html(:static, "<button>Save</button>")
    Process.put(:network_action_ran, false)

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        wait_for(session, Event.request(:request, ~r/api/), fn session ->
          Process.put(:network_action_ran, true)
          session
        end)
      end

    assert error.capability == :browser_network_events
    refute Process.get(:network_action_ran)
  end

  defp network_fixture do
    TestHTTPFixtures.register(fn request ->
      case request.path do
        "/start" ->
          %{
            body:
              html("""
              <button onclick="fetch('api?source=button', {
                method: 'POST',
                headers: {'x-fluffy': 'network-test'},
                body: 'payload'
              })">Save</button>
              """)
          }

        "/api" ->
          %{
            status: 207,
            headers: [{"content-type", "application/json"}],
            body: ~s({"saved":true})
          }
      end
    end)
  end

  defp start_test_session do
    start_session(:playwright,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end

  defp html(body), do: "<!doctype html><html><body>#{body}</body></html>"
end
