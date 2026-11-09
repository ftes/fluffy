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

  describe "to_be_in_viewport" do
    @html ~s(<div id="top" style="height: 200px">Top</div>
              <div style="height: 4000px">Gap</div>
              <div id="tall" style="height: 8000px">Tall</div>)

    test "follows scrolling, and is retried and negated like other assertions" do
      with_html(:playwright, @html, fn session ->
        tall = by_css("#tall")

        session
        |> expect(to_be_in_viewport(by_css("#top")))
        |> expect(not_(to_be_in_viewport(tall)))
        |> scroll_into_view_if_needed(tall)
        |> expect(to_be_in_viewport(tall))
        |> expect(not_(to_be_in_viewport(by_css("#top"))))
      end)
    end

    test "takes a minimal ratio" do
      with_html(:playwright, @html, fn session ->
        tall = by_css("#tall")

        session
        |> scroll_into_view_if_needed(tall)
        |> expect(to_be_in_viewport(tall, ratio: 0.01))
        |> expect(not_(to_be_in_viewport(tall, ratio: 0.99)))
      end)
    end

    test "fails naming the ratio" do
      with_html(:playwright, @html, fn session ->
        assert_raise ExUnit.AssertionError, ~r/to be in viewport with ratio 0.5/, fn ->
          expect(session, to_be_in_viewport(by_css("#tall"), ratio: 0.5, timeout: 100))
        end
      end)
    end

    test "rejects an unknown option" do
      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:signal/, fn ->
        to_be_in_viewport(by_css("#tall"), signal: :none)
      end
    end
  end

  describe "add_init_script" do
    test "runs before the page's own scripts in documents loaded afterwards" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert Playwright.add_init_script(session, "window.seeded = (window.seeded || 0) + 1") == session

      # The current document was loaded before the script was added.
      assert Playwright.evaluate(session, "window.seeded === undefined")

      session = visit(session, "/harness")
      assert Playwright.evaluate(session, "window.seeded") == 1
    end

    test "passes arg to a function, and takes a source map" do
      session =
        :playwright
        |> session_for_html("<p>Harness</p>")
        |> Playwright.add_init_script("name => { window.greeting = name }", "Harry")
        |> Playwright.add_init_script(%{content: "window.fromContent = true"})
        |> visit("/harness")

      assert Playwright.evaluate(session, "window.greeting") == "Harry"
      assert Playwright.evaluate(session, "window.fromContent")
    end

    @tag :tmp_dir
    test "takes a path to a script file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "init.js")
      File.write!(path, "window.fromPath = true")

      session =
        :playwright
        |> session_for_html("<p>Harness</p>")
        |> Playwright.add_init_script(%{path: path})
        |> visit("/harness")

      assert Playwright.evaluate(session, "window.fromPath")
    end

    test "rejects an arg with a source map" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert_raise ArgumentError, ~r/script map takes no arg/, fn ->
        Playwright.add_init_script(session, %{content: "window.seeded = true"}, "Harry")
      end
    end

    test "covers new pages of the session" do
      session = :playwright |> session_for_html("<p>Harness</p>") |> Playwright.add_init_script("window.seeded = true")

      other = session |> new_page() |> then(&switch_page(session, &1)) |> visit("/harness")
      assert Playwright.evaluate(other, "window.seeded")
    end

    test "covers popups of the session" do
      session =
        :playwright
        |> session_for_html("<p>Harness</p>")
        |> Playwright.add_init_script("window.seeded = true")

      pending = wait_for(session, Fluffy.Event.popup())
      Playwright.evaluate(session, "window.open('/harness'); true")
      assert Playwright.evaluate(switch_page(session, await(pending)), "window.seeded")
    end
  end

  describe "wait_for_function" do
    test "waits for a truthy expression and returns the session" do
      session = session_for_html(:playwright, "<p>Harness</p>")
      Playwright.evaluate(session, "setTimeout(() => { window.editorReady = true }, 100); true")

      assert Playwright.wait_for_function(session, "window.editorReady === true") == session
    end

    test "passes arg to a function and is pipeable" do
      session =
        :playwright
        |> session_for_html("<p>Harness</p>")
        |> Playwright.wait_for_function("min => window.innerWidth > min", 10)
        |> Playwright.wait_for_function("() => true", nil, polling: 50, timeout: 1_000)

      assert Playwright.evaluate(session, "1 + 1") == 2
    end

    test "fails after timeout: and leaves the session usable" do
      session = session_for_html(:playwright, "<p>Harness</p>")
      started = System.monotonic_time(:millisecond)

      assert_raise Fluffy.OperationError, ~r/wait_for_function.*[Tt]imeout/s, fn ->
        Playwright.wait_for_function(session, "() => false", nil, timeout: 100)
      end

      assert System.monotonic_time(:millisecond) - started < 5_000
      assert Playwright.evaluate(session, "1 + 1") == 2
    end

    test "is bounded by the session's timeout, even while a script blocks the page" do
      session = :playwright |> session_for_html("<p>Harness</p>") |> short_timeout()

      # The freeze runs inside the evaluate, so it is in place before the wait reaches the page.
      assert_raise RuntimeError, ~r/evaluate did not finish within 1000ms/, fn ->
        Playwright.evaluate(session, "() => { while (true) {} }")
      end

      started = System.monotonic_time(:millisecond)

      assert_raise RuntimeError, ~r/document check within 1000ms/, fn ->
        Playwright.wait_for_function(session, "() => false")
      end

      # The default session timeout is much longer; failure artifacts can add a few seconds.
      assert System.monotonic_time(:millisecond) - started < 10_000
    end

    test "reports a timeout, usually Playwright's own rather than Fluffy's backstop" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert_raise Fluffy.OperationError, ~r/waitForFunction: Timeout 100ms exceeded|Timeout 100ms exceeded during/, fn ->
        Playwright.wait_for_function(session, "() => false", nil, timeout: 100)
      end
    end

    test "raises when the page closes during the wait" do
      session = session_for_html(:playwright, "<p>Harness</p>")
      pending = wait_for(session, Fluffy.Event.popup())
      Playwright.evaluate(session, "window.open('/harness'); true")
      popup = switch_page(session, await(pending))
      Playwright.evaluate(popup, "setTimeout(() => window.close(), 500); true")

      assert_raise Fluffy.OperationError, ~r/wait_for_function.*closed/is, fn ->
        Playwright.wait_for_function(popup, "() => false", nil, timeout: 10_000)
      end
    end

    test "adopts a navigation that happens during the wait" do
      session = session_for_html(:playwright, "<p>Harness</p>")
      Playwright.evaluate(session, "setTimeout(() => { location.href = #{JSON.encode!(chamber())} }, 50); true")

      session
      |> Playwright.wait_for_function("document.body.textContent.includes('The guardian sleeps')")
      |> expect(page_to_have_url("/chamber"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    test "rejects unknown options" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:signal/, fn ->
        Playwright.wait_for_function(session, "() => true", nil, signal: :none)
      end
    end
  end

  # Setup runs under the default timeout; only the blocked part runs under 1s.
  defp short_timeout(session) do
    Fluffy.Session.put_context(session, %{Fluffy.Session.context(session) | timeout: 1_000})
  end

  defp with_html(driver, html, fun), do: fun.(session_for_html(driver, html))

  for driver <- [:static, :live] do
    @tag driver: driver
    test "to_be_in_viewport requires a browser with #{driver}" do
      session =
        case unquote(driver) do
          :static -> session_for_html(:static, "<p>Top</p>")
          :live -> :phoenix |> start_session() |> visit("/live/potions")
        end

      for expectation <- [to_be_in_viewport(by_css("p")), not_(to_be_in_viewport(by_css("p")))] do
        error = assert_raise Fluffy.CapabilityError, fn -> expect(session, expectation) end
        assert error.driver == unquote(driver)
        assert Fluffy.Capability.status(error.capability, unquote(driver)) == :browser_only
      end
    end
  end

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

    for operation <- [
          fn -> Playwright.add_init_script(session, "window.x = 1") end,
          fn -> Playwright.wait_for_function(session, "true") end
        ] do
      error = assert_raise Fluffy.CapabilityError, operation
      assert Fluffy.Capability.status(error.capability, :static) == :browser_only
    end

    for input <- [fn -> Keyboard.press(session, "a") end, fn -> Mouse.down(session) end] do
      error = assert_raise Fluffy.CapabilityError, input
      assert Fluffy.Capability.status(error.capability, :static) == :browser_only
    end

    assert :ok = close_session(session)
  end
end
