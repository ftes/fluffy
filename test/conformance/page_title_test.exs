defmodule Fluffy.Conformance.PageTitleTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- Drivers.backends() do
    @tag driver: driver
    test "matches a static page title with #{driver}", %{driver: driver} do
      driver
      |> start_session()
      |> visit("/chamber")
      |> expect(Fluffy.Expect.page_to_have_title("  Sleeping\n chamber  "))
      |> expect(Fluffy.Expect.page_to_have_title(~r/^Sleeping chamber$/))
      |> expect(not_(Fluffy.Expect.page_to_have_title("Another title")))
    end

    @tag driver: driver
    test "retries a changing LiveView page title with #{driver}", %{driver: driver} do
      driver
      |> start_session()
      |> visit("/live/enchanted-title")
      |> expect(Fluffy.Expect.page_to_have_title("Sealed chamber"))
      |> click(by_role(:button, name: "Change title"))
      |> expect(Fluffy.Expect.page_to_have_title(~r/^Revealed chamber$/))
    end
  end
end
