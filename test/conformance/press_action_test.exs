defmodule Fluffy.Conformance.PressActionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "pressing Space focuses and toggles a checkbox with #{driver}" do
      checkbox = by_role(:checkbox, name: "Updates")
      html = ~s(<label><input type="checkbox">Updates</label>)

      with_html(unquote(driver), html, fn session ->
        session
        |> press(checkbox, "Space")
        |> expect(checked(checkbox))
        |> expect(focused(checkbox))
        |> press(checkbox, "Space")
        |> expect(not_(checked(checkbox)))
      end)
    end

    @tag driver: driver
    test "pressing Tab advances focus in document order with #{driver}" do
      first = by_label("First")
      second = by_label("Second")
      html = ~s(<input aria-label="First"><input aria-label="Second">)

      with_html(unquote(driver), html, fn session ->
        session
        |> press(first, "Tab")
        |> expect(not_(focused(first)))
        |> expect(focused(second))
      end)
    end

    @tag driver: driver
    test "pressing Tab follows positive tabindex before document order with #{driver}" do
      first = by_label("First")
      third = by_label("Third")

      html = """
      <input aria-label="First" tabindex="2">
      <input aria-label="Second" tabindex="1">
      <input aria-label="Third">
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> press(first, "Tab")
        |> expect(not_(focused(first)))
        |> expect(focused(third))
      end)
    end

    @tag driver: driver
    test "press rejects keys outside the shared subset with #{driver}" do
      with_html(unquote(driver), ~s(<input aria-label="Name">), fn session ->
        assert_raise ArgumentError, ~r/unsupported key/, fn ->
          press(session, by_label("Name"), "ArrowDown")
        end
      end)
    end
  end

  @tag driver: :playwright
  test "the browser oracle submits a form when Enter is pressed in a text field" do
    html = """
    <form onsubmit="event.preventDefault(); result.value = 'submitted'">
      <input aria-label="Name">
      <button>Submit</button>
    </form>
    <input id="result" aria-label="Result" value="waiting">
    """

    with_html(:playwright, html, fn session ->
      session
      |> press(by_label("Name"), "Enter")
      |> expect(value(by_label("Result"), "submitted"))
    end)
  end

  test "Static keeps Enter inert outside a form" do
    session = session_for_html(:static, ~s(<input aria-label="Name">))

    session = press(session, by_label("Name"), "Enter")
    assert %Fluffy.Session{} = session
    assert expect(session, focused(by_label("Name")))
  end

  defp with_html(driver, html, fun) do
    session = session_for_html(driver, html, base_url: Fluffy.TestServer.base_url())
    fun.(session)
  end
end
