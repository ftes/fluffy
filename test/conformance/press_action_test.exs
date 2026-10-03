defmodule Fluffy.Conformance.PressActionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  @tag driver: :playwright
  test "pressing Space focuses and toggles a checkbox with Playwright" do
    checkbox = by_role(:checkbox, name: "Updates")
    html = ~s(<label><input type="checkbox">Updates</label>)

    with_html(:playwright, html, fn session ->
      session
      |> press(checkbox, "Space")
      |> expect(to_be_checked(checkbox))
      |> expect(to_be_focused(checkbox))
      |> press(checkbox, "Space")
      |> expect(not_(to_be_checked(checkbox)))
    end)
  end

  @tag driver: :playwright
  test "pressing Tab advances focus in document order with Playwright" do
    first = by_label("First")
    second = by_label("Second")
    html = ~s(<input aria-label="First"><input aria-label="Second">)

    with_html(:playwright, html, fn session ->
      session
      |> press(first, "Tab")
      |> expect(not_(to_be_focused(first)))
      |> expect(to_be_focused(second))
    end)
  end

  @tag driver: :playwright
  test "pressing Tab follows positive tabindex before document order with Playwright" do
    first = by_label("First")
    third = by_label("Third")

    html = """
    <input aria-label="First" tabindex="2">
    <input aria-label="Second" tabindex="1">
    <input aria-label="Third">
    """

    with_html(:playwright, html, fn session ->
      session
      |> press(first, "Tab")
      |> expect(not_(to_be_focused(first)))
      |> expect(to_be_focused(third))
    end)
  end

  test "Static rejects all keyboard actions" do
    session = session_for_html(:static, ~s(<input aria-label="Name">))

    for key <- ["Enter", "Space", "Tab", "Backspace", "ArrowDown", "ControlOrMeta+A", "a"] do
      error = assert_raise Fluffy.CapabilityError, fn -> press(session, by_label("Name"), key) end
      assert error.driver == :static
      assert error.capability == :press
    end
  end

  @tag driver: :playwright
  test "Playwright supports editing keys, characters, and modifier combinations" do
    with_html(:playwright, ~s(<input aria-label="Name">), fn session ->
      name = by_label("Name")

      session
      |> fill(name, "abc")
      |> press(name, "End")
      |> press(name, "Backspace")
      |> expect(to_have_value(name, "ab"))
      |> press(name, "ArrowLeft")
      |> press(name, "Delete")
      |> expect(to_have_value(name, "a"))
      |> press(name, "ControlOrMeta+A")
      |> press(name, "Z")
      |> expect(to_have_value(name, "Z"))
    end)
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
      |> expect("Result" |> by_label() |> to_have_value("submitted"))
    end)
  end

  defp with_html(driver, html, fun) do
    session = session_for_html(driver, html, base_url: Fluffy.TestServer.base_url())
    fun.(session)
  end
end
