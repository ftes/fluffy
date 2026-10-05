defmodule Fluffy.Conformance.CheckedLocatorTest do
  use Fluffy.TestCase, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "checked selectors follow user input without changing default attributes with #{driver}", %{driver: driver} do
      html = """
      <form>
        <label><input id="enabled" type="checkbox" checked> Enabled</label>
        <label><input id="red" type="radio" name="colour" checked> Red</label>
        <label><input id="blue" type="radio" name="colour"> Blue</label>
        <button type="reset">Reset</button>
      </form>
      """

      driver
      |> session_for_html(html, base_url: Fluffy.TestServer.base_url())
      |> expect("input:checked" |> by_css() |> to_have_count(2))
      |> uncheck(by_css("#enabled:checked"))
      |> check(by_css("#blue:not(:checked)"))
      |> expect("#blue:checked" |> by_css() |> to_have_count(1))
      |> expect("#enabled:checked, #red:checked" |> by_css() |> to_have_count(0))
      |> expect("input[checked]" |> by_css() |> to_have_count(2))
      |> expect("form" |> by_css() |> filter(has: by_css("#blue:checked")) |> to_have_count(1))
      |> expect("form" |> by_css() |> filter(has_not: by_css("#red:checked")) |> to_have_count(1))
      |> click(by_role(:button, name: "Reset"))
      |> expect("#enabled:checked, #red:checked" |> by_css() |> to_have_count(if(driver == :playwright, do: 2, else: 0)))
      |> expect("#blue:checked" |> by_css() |> to_have_count(if(driver == :playwright, do: 0, else: 1)))
    end

    @tag driver: driver
    test "checked option selectors follow implicit, single and multiple selections with #{driver}", %{driver: driver} do
      html = """
      <select aria-label="Default"><option disabled>Disabled</option><option>First</option><option>Second</option></select>
      <section><select aria-label="Explicit"><option selected>First</option><option>Second</option></select></section>
      <select aria-label="Multiple" multiple><option selected>First</option><option>Second</option></select>
      <select aria-label="List" size="2"><option>First</option><option>Second</option></select>
      """

      driver
      |> session_for_html(html, base_url: Fluffy.TestServer.base_url())
      |> expect("option:checked" |> by_css() |> to_have_count(3))
      |> expect("Default" |> by_label() |> by_css("option:checked") |> filter(has_text: "First") |> to_have_count(1))
      |> expect("List" |> by_label() |> by_css("option:checked") |> to_have_count(0))
      |> select_option(by_label("Default"), "Second")
      |> select_option(by_label("Explicit"), "Second")
      |> select_option(by_label("Multiple"), ["First", "Second"])
      |> expect("option:checked" |> by_css() |> filter(has_text: "Second") |> to_have_count(3))
      |> expect("Default" |> by_label() |> by_css("option:checked") |> filter(has_text: "Second") |> to_have_count(1))
      |> expect("Explicit" |> by_label() |> by_css("option:checked") |> filter(has_text: "Second") |> to_have_count(1))
      |> expect("Explicit" |> by_label() |> by_css("option[selected]") |> filter(has_text: "First") |> to_have_count(1))
      |> select_option(by_label("Multiple"), "Second")
      |> expect("Multiple" |> by_label() |> by_css("option:checked") |> to_have_count(1))
    end

    @tag driver: driver
    test "checked rewriting respects quoted values and escaped colons with #{driver}", %{driver: driver} do
      html = ~s(<input id="literal:checked" data-note=":checked" type="checkbox" checked>)

      driver
      |> session_for_html(html, base_url: Fluffy.TestServer.base_url())
      |> expect(~s([data-note=":checked"]:checked) |> by_css() |> to_have_count(1))
      |> expect(~S(#literal\:checked:checked) |> by_css() |> to_have_count(1))
      |> uncheck(by_css(~s([data-note=":checked"])))
      |> expect(~s([data-note=":checked"]:checked) |> by_css() |> to_have_count(0))
      |> expect(~S(#literal\:checked) |> by_css() |> to_have_count(1))
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "state-dependent check locators dispatch changes to the original control after click patches with #{driver}", %{
      driver: driver
    } do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> check(by_css("#enabled:not(:checked)"))
      |> expect("Checkbox clicks: 1" |> by_text(exact: true) |> to_be_visible())
      |> expect("#enabled:checked" |> by_css() |> to_have_count(1))
      |> uncheck(by_css("#enabled:checked"))
      |> expect("Checkbox clicks: 2" |> by_text(exact: true) |> to_be_visible())
      |> expect("Event targets: profile/enabled, profile/enabled" |> by_text(exact: true) |> to_be_visible())
      |> expect("#enabled:checked" |> by_css() |> to_have_count(0))
    end

    @tag driver: driver
    test "LiveView checked selectors read user input before it is rendered by the server with #{driver}", %{
      driver: driver
    } do
      driver
      |> start_test_session()
      |> visit("/live/checked-controls")
      |> check(by_label("Enabled"))
      |> select_option(by_label("Colour"), "green")
      |> expect("#enabled:checked" |> by_css() |> to_have_count(1))
      |> expect("#enabled[checked]" |> by_css() |> to_have_count(0))
      |> expect("option:checked[value=green]" |> by_css() |> to_have_count(1))
      |> expect("option[selected][value=red]" |> by_css() |> to_have_count(1))
      |> uncheck(by_css("#enabled:checked"))
      |> expect("#enabled:checked" |> by_css() |> to_have_count(0))
    end

    @tag driver: driver
    test "focused select protection during a LiveView patch is browser-specific with #{driver}", %{driver: driver} do
      topic = "checked-controls-#{System.unique_integer([:positive])}"
      field = by_label("Colour")

      # Phoenix adopts the changed server selection. The browser's LiveView
      # patcher protects the current value while this single select has focus.
      expected = if driver == :playwright, do: "green", else: "blue"

      driver
      |> start_test_session()
      |> visit("/live/checked-controls?topic=#{topic}")
      |> select_option(field, "green")
      |> focus(field)
      |> expect("option:checked[value=green]" |> by_css() |> to_have_count(1))
      |> tap(fn _session -> Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, :choose_blue) end)
      |> expect("Revision 1" |> by_text(exact: true) |> to_be_visible())
      |> expect(to_be_focused(field))
      |> expect(to_have_value(field, expected))
      |> expect("option:checked[value=#{expected}]" |> by_css() |> to_have_count(1))
    end

    @tag driver: driver
    test "unchanged checked attributes during a LiveView patch have backend-specific reconciliation with #{driver}", %{
      driver: driver
    } do
      topic = "checked-controls-#{System.unique_integer([:positive])}"
      field = by_label("Enabled")

      # Phoenix preserves a local checked property when its rendered attribute
      # has not changed. The browser's patcher can restore the server default.
      expected = driver == :phoenix

      driver
      |> start_test_session()
      |> visit("/live/checked-controls?topic=#{topic}")
      |> check(field)
      |> blur(field)
      |> expect("#enabled:checked" |> by_css() |> to_have_count(1))
      |> tap(fn _session -> Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, :choose_blue) end)
      |> expect("Revision 1" |> by_text(exact: true) |> to_be_visible())
      |> expect(to_be_checked(field, checked: expected))
      |> expect("#enabled:checked" |> by_css() |> to_have_count(if(expected, do: 1, else: 0)))
    end
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
