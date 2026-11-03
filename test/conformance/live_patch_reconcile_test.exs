defmodule Fluffy.Conformance.LivePatchReconcileTest do
  use Fluffy.TestCase, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "checked state stays on its id-less radio when a patch inserts an element before it with #{driver}", %{
      driver: driver
    } do
      driver
      |> start_test_session()
      |> visit("/live/radio-shift")
      |> check(by_role(:radio, name: "c"))
      |> expect("Choice: c" |> by_text() |> to_be_visible())
      |> expect(to_be_checked(by_role(:radio, name: "c")))
      |> expect("input[type=radio]:checked" |> by_css() |> to_have_count(1))
    end

    @tag driver: driver
    test "a server-rendered radio choice clears a local choice in its group with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/radio-shift?override=a")
      |> check(by_role(:radio, name: "c"))
      |> expect("Choice: c" |> by_text() |> to_be_visible())
      |> expect(to_be_checked(by_role(:radio, name: "a")))
      |> expect("input[type=radio]:checked" |> by_css() |> to_have_count(1))
    end

    @tag driver: driver
    test "local checkbox state does not move to a shifted id-less sibling with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/radio-shift")
      |> check(by_role(:checkbox, name: "y"))
      |> expect("Changed: true" |> by_text() |> to_be_visible())
      |> expect(to_be_checked(by_role(:checkbox, name: "x"), checked: false))
    end

    @tag driver: driver
    test "a select's choice does not move to a shifted id-less select with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/shifted-controls")
      |> select_option(by_label("Second"), "y")
      |> expect("Changed: true" |> by_text() |> to_be_visible())
      |> expect(to_have_value(by_label("First"), "x"))
      |> expect(to_have_value(by_label("Second"), "x"))
    end

    @tag driver: driver
    test "the focused input's text follows the element LiveView patches into its place with #{driver}", %{
      driver: driver
    } do
      # LiveView pairs id-less elements by position and protects the focused
      # element's value, so the typed text lands on the inserted Note field.
      driver
      |> start_test_session()
      |> visit("/live/shifted-controls")
      |> fill(by_label("Alpha"), "typed")
      |> expect("Changed: true" |> by_text() |> to_be_visible())
      |> expect(to_have_value(by_label("Note"), "typed"))
      |> expect(to_have_value(by_label("Alpha"), ""))
    end

    @tag driver: driver
    test "phx-patch-focused lets the server value replace focused text with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/shifted-controls")
      |> fill(by_label("Patched"), "typed")
      |> expect("Changed: true" |> by_text() |> to_be_visible())
      |> expect(to_have_value(by_label("Patched"), "server"))
    end
  end

  defp start_test_session(driver) do
    start_session(driver, base_url: Fluffy.TestServer.base_url(), endpoint: Fluffy.TestWeb.Endpoint)
  end
end
