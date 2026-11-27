defmodule Fluffy.Conformance.FilterDiagnosticsTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Locator

  alias Fluffy.Support.Web.FacadeLocatorsLive

  for driver <- Drivers.phoenix() do
    @tag driver: driver
    test "a missing action shows matches before its final text filter with #{driver}", %{driver: driver} do
      session = scopes_session(driver)
      prefix = within(by_css("p"), by_css("#one"))
      locator = filter(prefix, has_text: ~r/^Out/)

      error = assert_raise Fluffy.OperationError, fn -> click(session, locator, timeout: :once) end

      assert %Fluffy.StrictnessError{locator: ^locator, candidates: []} = error.cause
      assert error.message =~ "Matches before filter:"
      assert error.message =~ ~s(<p class="in">Inside</p>)
      refute error.message =~ "Outside"
    end
  end

  test "only a final has_text-only filter with prefix matches gets an explanation" do
    session = scopes_session(:static)
    paragraphs = by_css("p")

    for locator <- [
          filter(by_css("#absent"), has_text: "Lumos"),
          filter(paragraphs, has_text: "Lumos", visible: true),
          first(filter(paragraphs, has_text: "Lumos"))
        ] do
      error = assert_raise Fluffy.OperationError, fn -> click(session, locator) end
      refute error.message =~ "before filter"
    end
  end

  test "shows at most five snippets before the filter" do
    session = session_for_html(:static, Enum.map_join(1..6, &"<button>Spell #{&1}</button>"))
    locator = filter(by_role(:button), has_text: "Lumos")
    error = assert_raise Fluffy.OperationError, fn -> click(session, locator) end

    assert error.message =~ "<button>Spell 5</button>"
    refute error.message =~ "Spell 6"
  end

  defp scopes_session(:static), do: session_for_html(:static, FacadeLocatorsLive.markup("scopes"))
  defp scopes_session(:live), do: :phoenix |> start_session() |> visit("/live/facade-locators/scopes")
end
