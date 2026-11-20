defmodule Fluffy.Conformance.StaticVisitTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- Drivers.backends() do
    @tag driver: driver
    test "visits the static smoke page with #{driver}", %{driver: driver} do
      session =
        start_session(driver)

      session
      |> visit("/chamber")
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end
  end
end
