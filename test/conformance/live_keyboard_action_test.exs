defmodule Fluffy.Conformance.LiveKeyboardActionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Page

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "press dispatches matching keydown and keyup with browser payload and focus using #{driver}",
         %{driver: driver} do
      input = by_label("Element key", exact: true)

      driver
      |> live_session()
      |> visit("/live/keyboard")
      |> fill(input, "Ada")
      |> press(input, "Enter")
      |> expect(to_be_focused(input))
      |> expect("Event count: 2" |> by_text(exact: true) |> to_be_visible())
      |> expect("element-keydown:key=Enter;value=Ada;scope=element" |> by_text(exact: true) |> to_be_visible())
      |> expect("element-keyup:key=Enter;value=Ada;scope=element" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "phx-key filters case-insensitively and a non-match does not fall through to window handlers with #{driver}",
         %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/keyboard")
      |> press(by_label("Mismatched key", exact: true), "Enter")
      |> expect("Event count: 0" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "press dispatches window key handlers when the focused element has no direct binding with #{driver}",
         %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/keyboard")
      |> press(by_label("Window key", exact: true), "Enter")
      |> expect("Event count: 2" |> by_text(exact: true) |> to_be_visible())
      |> expect("window-keydown:key=Enter;value=none;scope=window" |> by_text(exact: true) |> to_be_visible())
      |> expect("window-keyup:key=Enter;value=none;scope=window" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "press honors a declarative phx-target with #{driver}", %{driver: driver} do
      input = by_label("Component key", exact: true)

      driver
      |> live_session()
      |> visit("/live/keyboard")
      |> fill(input, "targeted")
      |> press(input, "Enter")
      |> expect(
        "Component event: component-keydown:key=Enter;value=targeted;scope=component"
        |> by_text(exact: true)
        |> to_be_visible()
      )
    end

    @tag driver: driver
    test "declarative key events compose with one Enter default submission in browser order using #{driver}",
         %{driver: driver} do
      input = by_label("Search query", exact: true)

      driver
      |> live_session()
      |> visit("/live/keyboard")
      |> fill(input, "fluffy")
      |> press(input, "Enter")
      |> expect("Submitted: query=fluffy;commit=search" |> by_text(exact: true) |> to_be_visible())
      |> expect("Event count: 3" |> by_text(exact: true) |> to_be_visible())
      |> expect(
        "#keyboard-events > li:nth-child(1)"
        |> by_css()
        |> filter(has_text: "form-keydown:key=Enter;value=fluffy;scope=form")
        |> to_be_visible()
      )
      |> expect(
        "#keyboard-events > li:nth-child(2)"
        |> by_css()
        |> filter(has_text: "submit:key=none;value=fluffy;scope=search")
        |> to_be_visible()
      )
      |> expect(
        "#keyboard-events > li:nth-child(3)"
        |> by_css()
        |> filter(has_text: "window-keyup:key=Enter;value=none;scope=window")
        |> to_be_visible()
      )
    end

    @tag driver: driver
    test "a key handler patch is reconciled by the ordinary action navigation path with #{driver}",
         %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/keyboard")
      |> press(by_label("Patch key", exact: true), "Enter")
      |> expect(Page.to_have_url(Fluffy.TestServer.base_url() <> "/live/keyboard?step=patched"))
      |> expect("Step: patched" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "Tab dispatches keydown before moving focus and keyup on the newly focused element with #{driver}",
         %{driver: driver} do
      first = by_label("Tab first", exact: true)
      second = by_label("Tab second", exact: true)

      driver
      |> live_session()
      |> visit("/live/keyboard")
      |> press(first, "Tab")
      |> expect(to_be_focused(second))
      |> expect("Event count: 2" |> by_text(exact: true) |> to_be_visible())
      |> expect(
        "#keyboard-events > li:nth-child(1)"
        |> by_css()
        |> filter(has_text: "tab-keydown:key=Tab;value=;scope=none")
        |> to_be_visible()
      )
      |> expect(
        "#keyboard-events > li:nth-child(2)"
        |> by_css()
        |> filter(has_text: "tab-keyup:key=Tab;value=;scope=none")
        |> to_be_visible()
      )
    end

    @tag driver: driver
    test "Space dispatches its browser key value through both declarative phases with #{driver}",
         %{
           driver: driver
         } do
      button = by_role(:button, name: "Space key", exact: true)

      driver
      |> live_session()
      |> visit("/live/keyboard")
      |> press(button, "Space")
      |> expect(to_be_focused(button))
      |> expect("Event count: 2" |> by_text(exact: true) |> to_be_visible())
      |> expect(
        "#keyboard-events > li:nth-child(1)"
        |> by_css()
        |> filter(has_text: "space-keydown:key= ;value=;scope=space")
        |> to_be_visible()
      )
      |> expect(
        "#keyboard-events > li:nth-child(2)"
        |> by_css()
        |> filter(has_text: "space-keyup:key= ;value=;scope=space")
        |> to_be_visible()
      )
    end

    @tag driver: driver
    test "Space performs its structural checkbox activation after the key phases with #{driver}",
         %{driver: driver} do
      checkbox = by_label("Space checkbox", exact: true)

      driver
      |> live_session()
      |> visit("/live/keyboard")
      |> press(checkbox, "Space")
      |> expect(to_be_checked(checkbox))
    end

    @tag driver: driver
    test "the default LiveSocket key payload has no synthesized modifier or repeat fields with #{driver}",
         %{driver: driver} do
      input = by_label("Payload key", exact: true)

      driver
      |> live_session()
      |> visit("/live/keyboard")
      |> fill(input, "metadata")
      |> press(input, "Enter")
      |> expect("Payload keys: key,scope,value" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "a keydown navigation uses the ordinary page adoption path with #{driver}", %{
      driver: driver
    } do
      driver
      |> live_session()
      |> visit("/live/keyboard")
      |> press(by_label("Navigate key", exact: true), "Enter")
      |> expect(Page.to_have_url(Fluffy.TestServer.base_url() <> "/live/secret-chamber"))
      |> expect("The secret chamber is open" |> by_text(exact: true) |> to_be_visible())
    end
  end

  test "Live keeps inline prevent-default handlers behind the keyboard default-action boundary" do
    session = :phoenix |> live_session() |> visit("/live/keyboard")

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        press(session, by_label("Inline key", exact: true), "Enter")
      end

    assert error.capability == :keyboard_default_action
    assert error.driver == :live
  end

  test "Live rejects client-side JS commands attached to a declarative key binding" do
    session = :phoenix |> live_session() |> visit("/live/keyboard")

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        press(session, by_label("Scripted key", exact: true), "Enter")
      end

    assert error.capability == :scripted_default_actions
    assert error.driver == :live
  end

  test "Live surfaces a crashing key handler as a LiveView error" do
    session = :phoenix |> live_session() |> visit("/live/keyboard")

    assert_raise Fluffy.LiveViewError, fn ->
      press(session, by_label("Crash key", exact: true), "Enter")
    end
  end

  defp live_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
