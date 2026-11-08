defmodule Fluffy.Conformance.PlaywrightWrappersTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Playwright
  alias Fluffy.Playwright.Keyboard
  alias Fluffy.Playwright.Mouse

  @moduletag driver: :playwright

  defp chamber, do: Fluffy.TestServer.base_url() <> "/chamber"

  test "dblclick fires a double click and passes options through" do
    html = ~s|<button ondblclick="this.textContent = event.shiftKey ? 'shift' : 'twice'">Cast</button>|

    with_html(:playwright, html, fn session ->
      session
      |> dblclick(by_role(:button), trial: true)
      |> expect(to_be_visible(by_role(:button, name: "Cast")))
      |> dblclick(by_role(:button), modifiers: [:shift])
      |> expect(to_be_visible(by_role(:button, name: "shift")))
    end)
  end

  test "tap fires a tap on a touch context" do
    html = ~s|<button ontouchend="this.textContent = 'Tapped'">Cast</button>|

    :playwright
    |> session_for_html(html, browser_context: [has_touch: true])
    |> Playwright.tap(by_role(:button), [])
    |> expect(to_be_visible(by_role(:button, name: "Tapped")))
  end

  test "dispatch_event fires the event with its init" do
    html = ~s|<button onclick="this.textContent = 'detail ' + event.detail">Cast</button>|

    with_html(:playwright, html, fn session ->
      session
      |> dispatch_event(by_role(:button), "click", %{detail: 7})
      |> expect(to_be_visible(by_text("detail 7")))
      |> dispatch_event(by_role(:button), "click", nil, timeout: 1_000)
      |> expect(to_be_visible(by_text("detail 0")))
    end)
  end

  test "dispatch_event takes its init as a map, not options" do
    session = session_for_html(:playwright, "<button>Cast</button>")

    assert_raise FunctionClauseError, fn ->
      apply(Playwright, :dispatch_event, [session, by_role(:button), "click", [timeout: 100]])
    end
  end

  test "select_text selects a field's text" do
    session =
      :playwright
      |> session_for_html(~s(<input aria-label="Name" value="Hermione">))
      |> select_text(by_label("Name"), force: true)

    assert Playwright.evaluate(session, "document.activeElement.selectionEnd") == 8
    assert Playwright.evaluate(session, "document.activeElement.selectionStart") == 0
  end

  test "scroll_into_view_if_needed scrolls to the element" do
    html = ~s(<div style="height:5000px"></div><button>Far</button>)
    session = session_for_html(:playwright, html)
    assert Playwright.evaluate(session, "window.scrollY") == 0

    session = scroll_into_view_if_needed(session, by_role(:button))
    assert Playwright.evaluate(session, "window.scrollY") > 0
  end

  describe "screenshot" do
    setup do
      directory = Path.join(System.tmp_dir!(), "fluffy-shot-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(directory) end)
      %{directory: directory}
    end

    test "saves one element and leaves the page form working", %{directory: directory} do
      html = ~s(<button id="a" style="width:80px;height:40px">Cast</button><p id="m">Mask</p>)
      element = Path.join([directory, "nested", "element.png"])
      masked = Path.join(directory, "masked.jpg")
      page = Path.join(directory, "page.png")

      session =
        :playwright
        |> session_for_html(html)
        |> Playwright.screenshot(by_css("#a"), element)
        |> Playwright.screenshot(by_css("#a"), masked, type: :jpeg, quality: 50, mask: [by_css("#m")])
        |> Playwright.screenshot(page)

      assert <<0x89, "PNG", _rest::binary>> = File.read!(element)
      assert <<0xFF, 0xD8, _rest::binary>> = File.read!(masked)
      assert File.stat!(page).size > File.stat!(element).size
      expect(session, to_be_visible(by_role(:button)))
    end

    test "takes the path as an argument, and fails like an action", %{directory: directory} do
      session = session_for_html(:playwright, ~s(<input><input>))

      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:path/, fn ->
        Playwright.screenshot(session, by_css("input"), "/tmp/x.png", path: "/tmp/y.png")
      end

      error =
        assert_raise Fluffy.OperationError, fn ->
          Playwright.screenshot(session, by_css("input"), Path.join(directory, "x.png"), timeout: 100)
        end

      assert error.operation == :screenshot
    end
  end

  test "set_viewport_size resizes the active page" do
    session =
      :playwright
      |> session_for_html("<p>Hi</p>")
      |> set_viewport_size(%{width: 390, height: 844})

    assert Playwright.evaluate(session, "[window.innerWidth, window.innerHeight]") == [390, 844]
  end

  test "emulate_media changes media features and resets them with :null" do
    session = :playwright |> session_for_html("<p>Hi</p>") |> emulate_media(color_scheme: :dark)
    assert Playwright.evaluate(session, "matchMedia('(prefers-color-scheme: dark)').matches")

    session = emulate_media(session, media: :print)
    assert Playwright.evaluate(session, "matchMedia('print').matches")

    session = emulate_media(session, media: :null)
    refute Playwright.evaluate(session, "matchMedia('print').matches")
  end

  describe "Keyboard" do
    test "types, presses and holds keys on the focused element" do
      html = ~s|<input aria-label="Name" onkeydown="window.shift = event.shiftKey">|

      session =
        :playwright
        |> session_for_html(html)
        |> Playwright.focus(by_label("Name"))
        |> Keyboard.type("Ron", delay: 1)
        |> Keyboard.press("Backspace")
        |> Keyboard.insert_text("!")
        |> expect(to_have_value(by_label("Name"), "Ro!"))
        |> Keyboard.down("Shift")
        |> Keyboard.press("KeyA", delay: 1)
        |> Keyboard.up("Shift")

      assert Playwright.evaluate(session, "window.shift")
      expect(session, to_have_value(by_label("Name"), "Ro!A"))
    end

    test "fails with the key and leaves the session usable" do
      session = session_for_html(:playwright, "<p>Hi</p>")

      error = assert_raise Fluffy.OperationError, fn -> Keyboard.press(session, "NotAKey") end
      assert error.operation == :"Keyboard.press"
      assert is_nil(error.locator)
      assert error.message =~ "for the page"

      expect(session, to_be_visible(by_text("Hi")))
    end

    test "is bounded by its timeout while a script blocks the page" do
      html = ~s|<input aria-label="Name" onkeydown="const end = Date.now() + 1000; while (Date.now() < end) {}">|
      session = :playwright |> session_for_html(html) |> Playwright.focus(by_label("Name"))

      error =
        assert_raise Fluffy.OperationError, ~r/Timeout 100ms exceeded/, fn ->
          Keyboard.press(session, "a", timeout: 100)
        end

      assert %PlaywrightEx.TimeoutError{} = error.cause
    end
  end

  describe "Mouse" do
    setup do
      html = """
      <div id="a" style="position:fixed;left:10px;top:10px;width:80px;height:40px"
        onclick="this.textContent = event.detail === 2 ? 'Double' : 'Single'"
        onmouseenter="window.entered = true"
        onmousedown="window.down = event.button"
        onmouseup="window.up = event.button"
        onwheel="window.wheel = event.deltaY">Target</div>
      """

      %{session: session_for_html(:playwright, html)}
    end

    test "clicks and double-clicks at coordinates", %{session: session} do
      session
      |> Mouse.click(30, 20)
      |> expect(to_be_visible(by_text("Single")))
      |> Mouse.dblclick(30, 20, delay: 1)
      |> expect(to_be_visible(by_text("Double")))
    end

    test "moves, presses, releases and scrolls", %{session: session} do
      session =
        session
        |> Mouse.move(30, 20, steps: 2)
        |> Mouse.down(button: :right)
        |> Mouse.up(button: :right)
        |> Mouse.wheel(0, 40)

      assert Playwright.evaluate(session, "window.entered")
      assert Playwright.evaluate(session, "window.down") == 2
      assert Playwright.evaluate(session, "window.up") == 2
      assert Playwright.evaluate(session, "window.wheel") == 40
    end
  end

  describe "navigation" do
    test "dblclick adopts the document it navigates to" do
      html = ~s|<button ondblclick="location.href='/chamber'">Go</button>|

      :playwright
      |> session_for_html(html)
      |> dblclick(by_role(:button))
      |> expect(page_to_have_url(chamber()))
      |> then(&assert(Fluffy.Session.current_page(&1).url == chamber()))
    end

    test "Keyboard.press adopts the document it navigates to" do
      html = ~s|<input aria-label="Name" onkeydown="if (event.key === 'Enter') location.href='/chamber'">|

      :playwright
      |> session_for_html(html)
      |> Playwright.focus(by_label("Name"))
      |> Keyboard.press("Enter")
      |> expect(page_to_have_url(chamber()))
      |> then(&assert(Fluffy.Session.current_page(&1).url == chamber()))
    end

    test "Mouse.click adopts the document it navigates to" do
      html = ~s|<a href="/chamber" style="position:fixed;left:0;top:0;width:100px;height:40px">Go</a>|

      :playwright
      |> session_for_html(html)
      |> Mouse.click(30, 20)
      |> expect(page_to_have_url(chamber()))
      |> then(&assert(Fluffy.Session.current_page(&1).url == chamber()))
    end

    test "Keyboard.press leads to a LiveView the next action can use" do
      html = ~s|<form action="/live/potions"><input aria-label="Name"><button>Go</button></form>|

      :playwright
      |> session_for_html(html)
      |> Playwright.focus(by_label("Name"))
      |> Keyboard.press("Enter")
      |> expect(to_be_visible(by_label("First ingredient")))
      |> fill(by_label("First ingredient"), "ash")
      |> expect(to_be_visible(by_text("Last first: ash")))
    end
  end

  defp with_html(driver, html, fun), do: fun.(session_for_html(driver, html))

  test "browser actions reject Phoenix sessions" do
    session = start_session(:phoenix)
    button = by_role(:button)

    for operation <- [
          fn -> dblclick(session, button) end,
          fn -> Playwright.tap(session, button, []) end,
          fn -> dispatch_event(session, button, "click") end,
          fn -> select_text(session, button) end,
          fn -> scroll_into_view_if_needed(session, button) end,
          fn -> Playwright.screenshot(session, button, "/tmp/x.png") end,
          fn -> set_viewport_size(session, %{width: 1, height: 1}) end,
          fn -> emulate_media(session, color_scheme: :dark) end,
          fn -> Keyboard.press(session, "a") end,
          fn -> Keyboard.type(session, "a") end,
          fn -> Keyboard.down(session, "a") end,
          fn -> Keyboard.up(session, "a") end,
          fn -> Keyboard.insert_text(session, "a") end,
          fn -> Mouse.click(session, 0, 0) end,
          fn -> Mouse.dblclick(session, 0, 0) end,
          fn -> Mouse.down(session) end,
          fn -> Mouse.up(session) end,
          fn -> Mouse.move(session, 0, 0) end,
          fn -> Mouse.wheel(session, 0, 0) end
        ] do
      assert_raise Fluffy.CapabilityError, operation
    end

    for input <- [fn -> Keyboard.press(session, "a") end, fn -> Mouse.down(session) end] do
      error = assert_raise Fluffy.CapabilityError, input
      assert Fluffy.Capability.status(error.capability, :static) == :browser_only
    end

    assert :ok = close_session(session)
  end
end
