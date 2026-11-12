defmodule Fluffy.Conformance.LiveKeyboardActionTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Support.Server

  for key <- ["Enter", "Tab", "Space", " ", "Backspace", "Escape", "ArrowDown", "ControlOrMeta+A", "arbitrary"] do
    test "LiveView passes #{inspect(key)} unchanged to both handlers without phx-key filtering" do
      input = by_label("Element key", exact: true)

      session()
      |> press(input, unquote(key))
      |> expect("Event count: 2" |> by_text(exact: true) |> to_be_visible())
      |> expect("element-keydown:key=#{unquote(key)};value=;scope=element" |> by_text(exact: true) |> to_be_visible())
      |> expect("element-keyup:key=#{unquote(key)};value=;scope=element" |> by_text(exact: true) |> to_be_visible())
    end
  end

  test "Enter dispatches a keydown-only binding without submitting the form" do
    session()
    |> press(by_label("Search query", exact: true), "Enter")
    |> expect("Event count: 1" |> by_text(exact: true) |> to_be_visible())
    |> expect("form-keydown:key=Enter;value=;scope=form" |> by_text(exact: true) |> to_be_visible())
    |> expect("Submitted: none" |> by_text(exact: true) |> to_be_visible())
  end

  test "keydown-only and keyup-only bindings are supported" do
    first = by_label("Tab first", exact: true)
    second = by_label("Tab second", exact: true)

    session()
    |> press(first, "Tab")
    |> press(second, "Tab")
    |> expect("Event count: 2" |> by_text(exact: true) |> to_be_visible())
    |> expect("tab-keyup:key=Tab;value=;scope=none" |> by_text(exact: true) |> to_be_visible())
  end

  test "Space dispatches handlers without toggling a checkbox" do
    checkbox = by_label("Space checkbox", exact: true)

    session()
    |> press(checkbox, "Space")
    |> expect(not_(to_be_checked(checkbox)))
    |> expect("Event count: 2" |> by_text(exact: true) |> to_be_visible())
  end

  test "a target without keyboard bindings raises instead of reaching global handlers" do
    session = session()

    assert_raise ArgumentError, ~r/does not have phx-keydown or phx-window-keydown/, fn ->
      press(session, by_label("Window key", exact: true), "Enter")
    end
  end

  test "a keyup carries the element's value as its keydown does" do
    session()
    |> press(by_label("Valued key", exact: true), "Enter")
    |> expect("element-keydown:key=Enter;value=x;scope=none" |> by_text(exact: true) |> to_be_visible())
    |> expect("element-keyup:key=Enter;value=x;scope=none" |> by_text(exact: true) |> to_be_visible())
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "a key press carries the value a fill left with #{driver}", %{driver: driver} do
      input = by_label("Valued key", exact: true)

      driver
      |> session()
      |> fill(input, "Hermione")
      |> press(input, "Enter")
      |> expect("Event count: 2" |> by_text(exact: true) |> to_be_visible())
      |> expect("element-keydown:key=Enter;value=Hermione;scope=none" |> by_text(exact: true) |> to_be_visible())
      |> expect("element-keyup:key=Enter;value=Hermione;scope=none" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "a key press on an empty input carries an empty value with #{driver}", %{driver: driver} do
      driver
      |> session()
      |> press(by_label("Tab first", exact: true), "Tab")
      |> expect("tab-keydown:key=Tab;value=;scope=none" |> by_text(exact: true) |> to_be_visible())
    end
  end

  test "a keyup-only binding on a disabled element raises" do
    session = session()

    assert_raise ArgumentError, ~r/because it is disabled/, fn ->
      press(session, by_label("Disabled keyup key", exact: true), "Enter")
    end
  end

  test "window bindings are addressed on their own element" do
    session()
    |> press(by_css("#window-keydown"), "Escape")
    |> expect("Event count: 1" |> by_text(exact: true) |> to_be_visible())
    |> expect("window-keydown:key=Escape;value=none;scope=window" |> by_text(exact: true) |> to_be_visible())
  end

  test "a key event goes to its phx-target" do
    session()
    |> press(by_label("Component key", exact: true), "Escape")
    |> expect(
      "Component event: component-keydown:key=Escape;value=;scope=component"
      |> by_text(exact: true)
      |> to_be_visible()
    )
  end

  test "a press sends its keyup to a component that survives the keydown" do
    session()
    |> press(by_label("Component press key", exact: true), "a")
    |> expect("Component event: component-press-up:key=a" |> by_text(exact: true) |> to_be_visible())
  end

  test "a key handler patch is reconciled" do
    session()
    |> press(by_label("Patch key", exact: true), "Enter")
    |> expect(page_to_have_url(Server.base_url() <> "/live/keyboard?step=patched"))
    |> expect("Step: patched" |> by_text(exact: true) |> to_be_visible())
  end

  test "a keydown navigation stops dispatch and adopts the destination" do
    session()
    |> press(by_label("Navigate key", exact: true), "Enter")
    |> expect(page_to_have_url(Server.base_url() <> "/live/secret-chamber"))
    |> expect("The secret chamber is open" |> by_text(exact: true) |> to_be_visible())
  end

  test "Live surfaces a crashing key handler as a LiveView error" do
    session = session()

    assert_raise Fluffy.LiveViewError, fn ->
      press(session, by_label("Crash key", exact: true), "Enter")
    end
  end

  defp session(driver \\ :phoenix) do
    driver
    |> start_session(base_url: Server.base_url(), endpoint: Fluffy.Support.Web.Endpoint)
    |> visit("/live/keyboard")
  end
end
