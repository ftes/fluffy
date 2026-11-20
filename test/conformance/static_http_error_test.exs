defmodule Fluffy.Conformance.StaticHTTPErrorTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Support.HTTPFixtures

  for driver <- Drivers.backends() do
    @tag driver: driver
    test "renders an HTTP error response as a page with #{driver}", %{driver: driver} do
      fixture =
        HTTPFixtures.register(%{
          status: 404,
          body: "<!doctype html><html><body><h1>Owl not found</h1></body></html>"
        })

      session = start_session(driver)

      session
      |> visit(HTTPFixtures.path(fixture, "/missing"))
      |> expect("Owl not found" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(HTTPFixtures.url(fixture, "/missing")))
    end

    @tag driver: driver
    test "renders a redirect status without Location as a page with #{driver}", %{driver: driver} do
      fixture =
        HTTPFixtures.register(%{
          status: 302,
          body: "<!doctype html><html><body><h1>No redirect target</h1></body></html>"
        })

      session = start_session(driver)

      session
      |> visit(HTTPFixtures.path(fixture, "/no-location"))
      |> expect("No redirect target" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(HTTPFixtures.url(fixture, "/no-location")))
    end
  end

  test "Phoenix reports an unsupported navigation scheme precisely" do
    session = start_session(:phoenix)

    error =
      assert_raise Fluffy.CapabilityError, ~r/:visit \(:external_navigation\).*mailto/s, fn ->
        visit(session, "mailto:owlery@hogwarts.example")
      end

    assert %{operation: :visit, backend: :phoenix, driver: :unvisited} = error
  end

  test "Phoenix reports a same-scheme cross-origin navigation precisely" do
    session = start_session(:phoenix)

    error =
      assert_raise Fluffy.CapabilityError, ~r/external_navigation/, fn ->
        visit(session, "http://hogwarts.example/owls")
      end

    assert %{operation: :visit, driver: :unvisited} = error

    for {path, driver} <- [{"/chamber", :static}, {"/live/secret-chamber", :live}] do
      session = visit(session, path)

      error =
        assert_raise Fluffy.CapabilityError, fn ->
          visit(session, "https://ministry.example/")
        end

      assert %{operation: :visit, backend: :phoenix, driver: ^driver} = error
    end
  end

  test "Phoenix reports a redirect to an unsupported scheme with the call that followed it" do
    fixture = HTTPFixtures.register(%{status: 302, headers: [{"location", "mailto:owlery@hogwarts.example"}]})

    error =
      assert_raise Fluffy.CapabilityError, ~r/mailto/, fn ->
        :phoenix
        |> start_session()
        |> visit("/chamber")
        |> visit(HTTPFixtures.path(fixture, "/owl-post"))
      end

    assert %{operation: :visit, driver: :static} = error
  end

  test "Phoenix reports a link to an unsupported scheme with the click that followed it" do
    fixture =
      HTTPFixtures.register(%{
        body: ~s(<!doctype html><html><body><a href="mailto:owlery@hogwarts.example">Send an owl</a></body></html>)
      })

    session = :phoenix |> start_session() |> visit(HTTPFixtures.path(fixture, "/owlery"))

    error =
      assert_raise Fluffy.CapabilityError, ~r/:click \(:external_navigation\).*mailto/s, fn ->
        click(session, by_role(:link, name: "Send an owl"))
      end

    assert %{operation: :click, driver: :static} = error
  end
end
