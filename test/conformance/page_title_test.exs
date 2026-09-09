defmodule Fluffy.Conformance.PageTitleTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestWeb.Endpoint

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "matches a static page title with #{driver}", %{driver: driver} do
      driver
      |> start_session(
        base_url: Fluffy.TestServer.base_url(),
        endpoint: Endpoint
      )
      |> visit("/chamber")
      |> expect(Fluffy.Expect.page_to_have_title("  Sleeping\n chamber  "))
      |> expect(Fluffy.Expect.page_to_have_title(~r/^Sleeping chamber$/))
      |> expect(not_(Fluffy.Expect.page_to_have_title("Another title")))
    end

    @tag driver: driver
    test "retries a changing LiveView page title with #{driver}", %{driver: driver} do
      driver
      |> start_session(
        base_url: Fluffy.TestServer.base_url(),
        endpoint: Endpoint
      )
      |> visit("/live/enchanted-title")
      |> expect(Fluffy.Expect.page_to_have_title("Sealed chamber"))
      |> click(by_role(:button, name: "Change title"))
      |> expect(Fluffy.Expect.page_to_have_title(~r/^Revealed chamber$/))
    end
  end
end
