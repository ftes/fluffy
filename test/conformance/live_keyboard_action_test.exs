defmodule Fluffy.Conformance.LiveKeyboardActionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for key <- ["Enter", "Tab", "Space", " ", "Backspace", "Escape", "ArrowDown", "ControlOrMeta+A", "arbitrary"] do
    test "LiveView passes #{inspect(key)} unchanged to both handlers without phx-key filtering" do
      input = by_label("Element key", exact: true)

      session()
      |> press(input, unquote(key))
      |> expect(not_(to_be_focused(input)))
      |> expect("Event count: 2" |> by_text(exact: true) |> to_be_visible())
      |> expect("element-keydown:key=#{unquote(key)};value=none;scope=element" |> by_text(exact: true) |> to_be_visible())
      |> expect("element-keyup:key=#{unquote(key)};value=none;scope=element" |> by_text(exact: true) |> to_be_visible())
    end
  end

  test "Backspace does not edit the field or synthesize its value in the event payload" do
    input = by_label("Element key", exact: true)

    session()
    |> fill(input, "Ada")
    |> press(input, "Backspace")
    |> expect(to_have_value(input, "Ada"))
    |> expect("element-keydown:key=Backspace;value=none;scope=element" |> by_text(exact: true) |> to_be_visible())
  end

  test "Enter dispatches a keydown-only binding without submitting the form" do
    session()
    |> press(by_label("Search query", exact: true), "Enter")
    |> expect("Event count: 1" |> by_text(exact: true) |> to_be_visible())
    |> expect("form-keydown:key=Enter;value=none;scope=form" |> by_text(exact: true) |> to_be_visible())
    |> expect("Submitted: none" |> by_text(exact: true) |> to_be_visible())
  end

  test "Tab does not move focus and keyup-only bindings are supported" do
    first = by_label("Tab first", exact: true)
    second = by_label("Tab second", exact: true)

    session()
    |> focus(first)
    |> press(first, "Tab")
    |> expect(to_be_focused(first))
    |> press(second, "Tab")
    |> expect(to_be_focused(first))
    |> expect("Event count: 2" |> by_text(exact: true) |> to_be_visible())
    |> expect("tab-keyup:key=Tab;value=none;scope=none" |> by_text(exact: true) |> to_be_visible())
  end

  test "Space dispatches handlers without toggling a checkbox" do
    checkbox = by_label("Space checkbox", exact: true)

    session()
    |> press(checkbox, "Space")
    |> expect(not_(to_be_checked(checkbox)))
    |> expect("Event count: 2" |> by_text(exact: true) |> to_be_visible())
  end

  test "a target without keyboard bindings uses LiveViewTest's error instead of global handlers" do
    session = session()

    assert_raise ArgumentError, ~r/does not have phx-keydown or phx-window-keydown/, fn ->
      press(session, by_label("Window key", exact: true), "Enter")
    end
  end

  test "window bindings are addressed on their own element" do
    session()
    |> press(by_css("#window-keydown"), "Escape")
    |> expect("Event count: 1" |> by_text(exact: true) |> to_be_visible())
    |> expect("window-keydown:key=Escape;value=none;scope=window" |> by_text(exact: true) |> to_be_visible())
  end

  test "LiveViewTest handles phx-target" do
    session()
    |> press(by_label("Component key", exact: true), "Escape")
    |> expect(
      "Component event: component-keydown:key=Escape;value=;scope=component"
      |> by_text(exact: true)
      |> to_be_visible()
    )
  end

  test "a key handler patch is reconciled" do
    session()
    |> press(by_label("Patch key", exact: true), "Enter")
    |> expect(page_to_have_url(Fluffy.TestServer.base_url() <> "/live/keyboard?step=patched"))
    |> expect("Step: patched" |> by_text(exact: true) |> to_be_visible())
  end

  test "a keydown navigation stops dispatch and adopts the destination" do
    session()
    |> press(by_label("Navigate key", exact: true), "Enter")
    |> expect(page_to_have_url(Fluffy.TestServer.base_url() <> "/live/secret-chamber"))
    |> expect("The secret chamber is open" |> by_text(exact: true) |> to_be_visible())
  end

  test "Live surfaces a crashing key handler as a LiveView error" do
    session = session()

    assert_raise Fluffy.LiveViewError, fn ->
      press(session, by_label("Crash key", exact: true), "Enter")
    end
  end

  defp session do
    :phoenix
    |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Fluffy.TestWeb.Endpoint)
    |> visit("/live/keyboard")
  end
end
