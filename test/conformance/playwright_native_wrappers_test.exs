defmodule Fluffy.Conformance.PlaywrightNativeWrappersTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Playwright
  alias Fluffy.Route
  alias Fluffy.TestHTTPFixtures

  @moduletag driver: :playwright

  describe "options in the argument position" do
    test "evaluate takes options in place of the argument" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert Playwright.evaluate(session, "1 + 1", timeout: 1_000) == 2
      assert Playwright.evaluate(session, "value => value", "arg", timeout: 1_000) == "arg"
    end

    test "evaluate's timeout overrides the session's" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert_raise PlaywrightEx.TimeoutError, ~r/Timeout 100ms exceeded during evaluate/, fn ->
        Playwright.evaluate(session, "new Promise(() => {})", timeout: 100)
      end

      assert_raise PlaywrightEx.TimeoutError, ~r/Timeout 100ms exceeded during evaluate/, fn ->
        Playwright.evaluate(session, "new Promise(() => {})", nil, timeout: 100)
      end
    end

    test "evaluate rejects unknown options" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:signal/, fn ->
        Playwright.evaluate(session, "1", signal: :none)
      end
    end

    test "evaluate keeps other lists as JavaScript arrays" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert Playwright.evaluate(session, "value => Array.isArray(value) && value.length === 0", []) == true
      assert Playwright.evaluate(session, "value => value", [1, "two"]) == [1, "two"]
      assert Playwright.evaluate(session, "value => value", [%{a: 1}]) == [%{"a" => 1}]
      assert Playwright.evaluate(session, "value => Array.isArray(value)", [], timeout: 1_000) == true
    end

    test "wait_for_function takes options in place of the argument" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert Playwright.wait_for_function(session, "() => true", timeout: 1_000) == session
      assert Playwright.wait_for_function(session, "() => true", nil, timeout: 1_000) == session

      assert_raise Fluffy.OperationError, ~r/wait_for_function.*[Tt]imeout/s, fn ->
        Playwright.wait_for_function(session, "() => false", timeout: 100)
      end

      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:signal/, fn ->
        Playwright.wait_for_function(session, "() => true", signal: :none)
      end
    end

    test "wait_for_function keeps other lists as JavaScript arrays" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert Playwright.wait_for_function(session, "value => Array.isArray(value) && value.length === 0", []) == session
      assert Playwright.wait_for_function(session, "value => value[1] === 'two'", [1, "two"]) == session
    end
  end

  describe "to_have_css" do
    @html ~s|<style>#styled::before { content: "x"; color: rgb(0, 0, 255) }</style>
             <p id="styled" style="color: rgb(255, 0, 0)">Styled</p>|

    test "asserts a computed style, negated, by regular expression and on a pseudo-element" do
      target = by_css("#styled")

      :playwright
      |> session_for_html(@html)
      |> expect(to_have_css(target, "color", "rgb(255, 0, 0)"))
      |> expect(not_(to_have_css(target, "color", "rgb(0, 0, 0)")))
      |> expect(to_have_css(target, "color", ~r/^rgb\(255/))
      |> expect(to_have_css(target, "color", "rgb(0, 0, 255)", pseudo: :before))
    end

    test "fails naming the property" do
      session = session_for_html(:playwright, @html)

      assert_raise ExUnit.AssertionError, ~r/to have CSS color "red"/, fn ->
        expect(session, to_have_css(by_css("#styled"), "color", "red", timeout: 100))
      end
    end

    test "rejects an unknown option" do
      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:signal/, fn ->
        to_have_css(by_css("#styled"), "color", "red", signal: :none)
      end
    end
  end

  test "to_have_js_property asserts a primitive or an object, negated" do
    html = ~s(<input id="field" value="hello">)
    field = by_css("#field")

    session =
      :playwright
      |> session_for_html(html)
      |> expect(to_have_js_property(field, "value", "hello"))
      |> expect(not_(to_have_js_property(field, "value", "other")))
      |> expect(to_have_js_property(field, "disabled", false))

    Playwright.evaluate(session, "document.querySelector('#field').settings = {depth: 2}")
    expect(session, to_have_js_property(field, "settings", %{depth: 2}))

    assert_raise ExUnit.AssertionError, ~r/to have JS property value "other"/, fn ->
      expect(session, to_have_js_property(field, "value", "other", timeout: 100))
    end
  end

  describe "accessibility assertions" do
    test "to_have_role asserts the role, negated" do
      :playwright
      |> session_for_html("<button>Cast</button>")
      |> expect(to_have_role(by_text("Cast"), :button))
      |> expect(not_(to_have_role(by_text("Cast"), :link)))
    end

    test "to_have_accessible_name matches strings, regular expressions and ignore_case" do
      button = by_role(:button)

      :playwright
      |> session_for_html(~s(<button aria-label="Cast spell">x</button>))
      |> expect(to_have_accessible_name(button, "Cast spell"))
      |> expect(to_have_accessible_name(button, ~r/^Cast/))
      |> expect(to_have_accessible_name(button, "cast SPELL", ignore_case: true))
      |> expect(not_(to_have_accessible_name(button, "Other")))
    end

    test "to_have_accessible_description reads the described-by text" do
      field = by_label("Name")

      :playwright
      |> session_for_html(~s(<label>Name <input aria-describedby="hint"></label><p id="hint">Your full name</p>))
      |> expect(to_have_accessible_description(field, "Your full name"))
      |> expect(to_have_accessible_description(field, "your FULL name", ignore_case: true))
      |> expect(not_(to_have_accessible_description(field, "Other")))
    end

    test "to_have_accessible_error_message reads the error message" do
      field = by_label("Name")

      html =
        ~s(<label>Name <input aria-invalid="true" aria-errormessage="problem"></label><p id="problem">Too short</p>)

      :playwright
      |> session_for_html(html)
      |> expect(to_have_accessible_error_message(field, "Too short"))
      |> expect(to_have_accessible_error_message(field, ~r/short/))
      |> expect(to_have_accessible_error_message(field, "TOO short", ignore_case: true))
      |> expect(not_(to_have_accessible_error_message(field, "Other")))
    end

    test "fail naming the expectation" do
      session = session_for_html(:playwright, ~s(<button aria-label="Cast">x</button>))

      assert_raise ExUnit.AssertionError, ~r/to have accessible name "Other"/, fn ->
        expect(session, to_have_accessible_name(by_role(:button), "Other", timeout: 100))
      end

      assert_raise ExUnit.AssertionError, ~r/to have role :link/, fn ->
        expect(session, to_have_role(by_role(:button), :link, timeout: 100))
      end
    end
  end

  describe "to_have_screenshot" do
    @html ~s|<div id="box" style="width: 60px; height: 40px; background: rgb(0, 128, 0)"></div>|

    @tag :tmp_dir
    test "writes a missing baseline at path:, then compares against it", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "nested/box.png")
      box = by_css("#box")
      session = session_for_html(:playwright, @html)

      expect(session, to_have_screenshot(box, path: path))
      assert File.exists?(path)
      baseline = File.read!(path)

      expect(session, to_have_screenshot(box, path: path))
      assert File.read!(path) == baseline

      paint(session, "rgb(200, 0, 0)")

      assert_raise ExUnit.AssertionError, ~r/to match the screenshot at/, fn ->
        expect(session, to_have_screenshot(box, path: path))
      end

      assert File.read!(path) == baseline
      assert File.exists?(Path.join(tmp_dir, "nested/box-actual.png"))
      assert File.exists?(Path.join(tmp_dir, "nested/box-diff.png"))
      assert File.exists?(Path.join(tmp_dir, "nested/box-expected.png"))
    end

    @tag :tmp_dir
    test "negation compares against the baseline and needs one", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "box.png")
      box = by_css("#box")
      session = session_for_html(:playwright, @html)

      assert_raise ExUnit.AssertionError, ~r/not .*to match the screenshot at/s, fn ->
        expect(session, not_(to_have_screenshot(box, path: path)))
      end

      refute File.exists?(path)
      expect(session, to_have_screenshot(box, path: path))
      paint(session, "rgb(200, 0, 0)")
      expect(session, not_(to_have_screenshot(box, path: path, timeout: 2_000)))
    end

    @tag :tmp_dir
    test "page_to_have_screenshot compares the page", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "page.webp")
      session = session_for_html(:playwright, @html)

      session
      |> expect(page_to_have_screenshot(path: path))
      |> expect(page_to_have_screenshot(path: path, full_page: false, max_diff_pixels: 0))

      assert File.exists?(path)
      paint(session, "rgb(200, 0, 0)")

      assert_raise ExUnit.AssertionError, ~r/active page to match the screenshot at/, fn ->
        expect(session, page_to_have_screenshot(path: path))
      end
    end

    @tag :tmp_dir
    test "passes mask: as Fluffy locators", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "masked.png")
      box = by_css("#box")
      session = session_for_html(:playwright, @html)

      expect(session, to_have_screenshot(box, path: path, mask: [box]))
      paint(session, "rgb(200, 0, 0)")
      expect(session, to_have_screenshot(box, path: path, mask: [box]))
    end

    test "requires path:, and does not derive one from the test" do
      for missing <- [
            fn -> to_have_screenshot(by_css("#box")) end,
            fn -> to_have_screenshot(by_css("#box"), full_page: false) end,
            fn -> page_to_have_screenshot() end,
            fn -> page_to_have_screenshot(timeout: 100) end
          ] do
        assert_raise NimbleOptions.ValidationError, ~r/required :path option not found/, missing
      end
    end

    test "rejects options that bypass tracking" do
      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:signal/, fn ->
        to_have_screenshot(by_css("#box"), path: "x.png", signal: :none)
      end
    end

    defp paint(session, color) do
      Playwright.evaluate(session, "color => { document.querySelector('#box').style.background = color }", color)
    end
  end

  describe "aria snapshots" do
    @html ~s(<section id="panel"><h1>Potions</h1><button>Cast</button></section>)

    test "aria_snapshot returns the snapshot of the page or a locator" do
      session = session_for_html(:playwright, @html)

      assert Playwright.aria_snapshot(session) =~ ~s(button "Cast")
      assert Playwright.aria_snapshot(session, timeout: 2_000) =~ ~s(heading "Potions")
      assert Playwright.aria_snapshot(session, by_role(:button)) =~ ~s(button "Cast")
      refute Playwright.aria_snapshot(session, by_role(:button), timeout: 2_000) =~ "heading"
    end

    test "aria_snapshot raises for a missing locator and rejects unknown options" do
      session = session_for_html(:playwright, @html)

      assert_raise Fluffy.OperationError, ~r/aria_snapshot.*[Tt]imeout/s, fn ->
        Playwright.aria_snapshot(session, by_css("#missing"), timeout: 100)
      end

      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:signal/, fn ->
        Playwright.aria_snapshot(session, signal: :none)
      end
    end

    test "to_match_aria_snapshot compares a locator or the page, negated" do
      :playwright
      |> session_for_html(@html)
      |> expect(to_match_aria_snapshot(by_css("#panel"), ~s(- button "Cast")))
      |> expect(not_(to_match_aria_snapshot(by_css("#panel"), ~s(- button "Other"))))
      |> expect(page_to_match_aria_snapshot(~s(- heading "Potions" [level=1])))
      |> expect(not_(page_to_match_aria_snapshot(~s(- heading "Other"))))
    end

    test "to_match_aria_snapshot fails with the current snapshot when none is given" do
      session = session_for_html(:playwright, @html)

      assert_raise ExUnit.AssertionError, ~r/New snapshot:.*button "Cast"/s, fn ->
        expect(session, to_match_aria_snapshot(by_css("#panel"), ""))
      end
    end

    @tag tmp_dir: true
    test "to_match_aria_snapshot with path: writes a missing file, compares it and fails on a change", %{
      tmp_dir: tmp_dir
    } do
      session = session_for_html(:playwright, @html)
      file = Path.join(tmp_dir, "snapshots/panel.aria.yml")
      page_file = Path.join(tmp_dir, "page.aria.yml")

      ExUnit.CaptureIO.capture_io(fn ->
        session
        |> expect(to_match_aria_snapshot(by_css("#panel"), path: file))
        |> expect(page_to_match_aria_snapshot(path: page_file))
      end)

      assert File.read!(file) =~ ~s(button "Cast")
      assert File.read!(page_file) =~ ~s(button "Cast")

      session
      |> expect(to_match_aria_snapshot(by_css("#panel"), path: file))
      |> expect(page_to_match_aria_snapshot(path: page_file))

      changed = session_for_html(:playwright, String.replace(@html, "Cast", "Brew"))

      assert_raise ExUnit.AssertionError, ~r/to match the ARIA snapshot at .*panel\.aria\.yml/, fn ->
        expect(changed, to_match_aria_snapshot(by_css("#panel"), path: file, timeout: 100))
      end

      assert_raise ExUnit.AssertionError, ~r/active page to match the ARIA snapshot at .*page\.aria\.yml/, fn ->
        expect(changed, page_to_match_aria_snapshot(path: page_file, timeout: 100))
      end

      assert_raise ExUnit.AssertionError, ~r/not both/, fn ->
        expect(session, to_match_aria_snapshot(by_css("#panel"), "- button", path: file))
      end
    end

    test "to_match_aria_snapshot fails naming the expectation" do
      session = session_for_html(:playwright, @html)

      assert_raise ExUnit.AssertionError, ~r/to match the ARIA snapshot/, fn ->
        expect(session, to_match_aria_snapshot(by_css("#panel"), ~s(- button "Other"), timeout: 100))
      end

      assert_raise ExUnit.AssertionError, ~r/active page to match the ARIA snapshot/, fn ->
        expect(session, page_to_match_aria_snapshot(~s(- button "Other"), timeout: 100))
      end
    end
  end

  test "viewport_size returns the page's viewport" do
    session = session_for_html(:playwright, "<p>Harness</p>")
    size = %{width: 420, height: 300}

    assert session |> Playwright.set_viewport_size(size) |> Playwright.viewport_size() == size
  end

  describe "set_extra_http_headers" do
    test "sends the headers, replaces an earlier call and keeps the session's headers" do
      fixture = TestHTTPFixtures.register(fn _request -> %{body: "<p>Page</p>"} end)
      session = start_session(:playwright, headers: [{"x-session", "kept"}])

      assert Playwright.set_extra_http_headers(session, %{"X-First" => "1"}) == session
      visit(session, TestHTTPFixtures.path(fixture, "/first"))

      session
      |> Playwright.set_extra_http_headers(%{"x-second" => "2"})
      |> visit(TestHTTPFixtures.path(fixture, "/second"))

      first = headers(fixture, "/first")
      assert {"x-first", "1"} in first
      assert {"x-session", "kept"} in first

      second = headers(fixture, "/second")
      assert {"x-second", "2"} in second
      assert {"x-session", "kept"} in second
      refute List.keymember?(second, "x-first", 0)
    end

    test "overrides a header of the same name" do
      fixture = TestHTTPFixtures.register(fn _request -> %{body: "<p>Page</p>"} end)

      :playwright
      |> start_session(headers: [{"x-session", "start"}])
      |> Playwright.set_extra_http_headers(%{"X-Session" => "changed"})
      |> visit(TestHTTPFixtures.path(fixture, "/page"))

      assert {"x-session", "changed"} in headers(fixture, "/page")
    end

    defp headers(fixture, path) do
      fixture |> TestHTTPFixtures.requests() |> Enum.find(&(&1.path == path)) |> Map.fetch!(:headers)
    end
  end

  describe "add_script_tag and add_style_tag" do
    @tag :tmp_dir
    test "add_script_tag injects content, a file or a URL and is pipeable", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "script.js")
      File.write!(file, "window.fromFile = 'file'")

      fixture =
        TestHTTPFixtures.register(fn _request ->
          %{headers: [{"content-type", "text/javascript"}], body: "window.fromUrl = 'url'"}
        end)

      session =
        :playwright
        |> session_for_html("<p>Harness</p>")
        |> Playwright.add_script_tag(content: "window.fromContent = 'content'")
        |> Playwright.add_script_tag(path: file)
        |> Playwright.add_script_tag(url: TestHTTPFixtures.url(fixture, "/script.js"), timeout: 5_000)

      assert Playwright.evaluate(session, "[window.fromContent, window.fromFile, window.fromUrl]") ==
               ["content", "file", "url"]
    end

    @tag :tmp_dir
    test "add_style_tag injects content or a file and is pipeable", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "style.css")
      File.write!(file, "#file { color: rgb(4, 5, 6) }")

      :playwright
      |> session_for_html(~s(<p id="content">Content</p><p id="file">File</p>))
      |> Playwright.add_style_tag(content: "#content { color: rgb(1, 2, 3) }")
      |> Playwright.add_style_tag(path: file)
      |> expect(to_have_css(by_css("#content"), "color", "rgb(1, 2, 3)"))
      |> expect(to_have_css(by_css("#file"), "color", "rgb(4, 5, 6)"))
    end

    test "reject unknown options" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      for call <- [&Playwright.add_script_tag(session, &1), &Playwright.add_style_tag(session, &1)] do
        assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:signal/, fn -> call.(signal: :none) end
      end
    end
  end

  describe "wait_for_load_state" do
    test "waits for a state, with options in its place, and is pipeable" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert Playwright.wait_for_load_state(session) == session
      assert Playwright.wait_for_load_state(session, :domcontentloaded) == session
      assert Playwright.wait_for_load_state(session, :load, timeout: 1_000) == session
      assert Playwright.wait_for_load_state(session, timeout: 1_000) == session
      assert Playwright.wait_for_load_state(session, []) == session
    end

    test "rejects unknown options" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:signal/, fn ->
        Playwright.wait_for_load_state(session, :load, signal: :none)
      end
    end
  end

  describe "wait_for" do
    test "waits for each state and is pipeable" do
      session =
        session_for_html(:playwright, ~s(<p id="here">Here</p><p id="gone">Gone</p><p id="hidden" hidden>Hidden</p>))

      Playwright.evaluate(
        session,
        "setTimeout(() => { document.querySelector('#gone').remove(); document.body.append(Object.assign(document.createElement('p'), {id: 'late', textContent: 'Late'})) }, 100); true"
      )

      assert session
             |> wait_for(by_css("#late"), [])
             |> wait_for(by_css("#gone"), state: :detached)
             |> wait_for(by_css("#hidden"), state: :hidden)
             |> wait_for(by_css("#here"), state: :attached) == session
    end

    test "is bounded by timeout: and the session's timeout:" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert_raise Fluffy.OperationError, ~r/wait_for.*[Tt]imeout/s, fn ->
        wait_for(session, by_css("#missing"), timeout: 100)
      end

      bounded = start_session(:playwright, timeout: 300)
      started = System.monotonic_time(:millisecond)

      assert_raise Fluffy.OperationError, ~r/wait_for.*[Tt]imeout/s, fn ->
        wait_for(bounded, by_css("#missing"), [])
      end

      assert System.monotonic_time(:millisecond) - started < 5_000
    end

    test "rejects unknown options" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:signal/, fn ->
        wait_for(session, by_css("p"), signal: :none)
      end
    end
  end

  describe "locator scripts" do
    setup do
      [
        session:
          session_for_html(:playwright, """
          <ul><li id="one" data-n="1">One</li><li id="two" data-n="2">Two</li></ul>
          """)
      ]
    end

    test "evaluate runs on the locator's element and returns the value", %{session: session} do
      assert Playwright.evaluate(session, by_css("#one"), "element => element.textContent") == "One"
      assert Playwright.evaluate(session, by_css("#one"), "(element, arg) => element.id + arg", "!") == "one!"
      assert Playwright.evaluate(session, by_css("#one"), "(_, arg) => arg", [], timeout: 1_000) == []
      assert Playwright.evaluate(session, by_css("#one"), "element => element.id", timeout: 1_000) == "one"
    end

    test "evaluate on a string target still evaluates on the page", %{session: session} do
      assert Playwright.evaluate(session, "1 + 1") == 2
      assert Playwright.evaluate(session, "value => value", "arg") == "arg"
      assert Playwright.evaluate(session, "value => value", [], timeout: 1_000) == []
    end

    @tag timeout: 10_000
    test "evaluate on a locator is bounded after the element is found", %{session: session} do
      assert_raise Fluffy.OperationError, ~r/evaluate.*[Tt]imeout 300ms/s, fn ->
        Playwright.evaluate(session, by_css("#one"), "() => new Promise(() => {})", timeout: 300)
      end
    end

    test "wait_for_function on a locator raises when the page closes during the wait" do
      popup = closing_popup(~s(<p id="one">One</p>))

      assert_raise Fluffy.OperationError, ~r/wait_for_function.*closed/is, fn ->
        Playwright.wait_for_function(popup, by_css("#one"), "() => false", timeout: 10_000)
      end
    end

    test "reads raise when the page closes during them" do
      popup = closing_popup(~s(<p id="one">One</p>))

      assert_raise Fluffy.OperationError, ~r/evaluate.*closed/is, fn ->
        Playwright.evaluate(popup, by_css("#one"), "() => new Promise(() => {})", timeout: 10_000)
      end
    end

    test "evaluate on a locator is strict and bounded", %{session: session} do
      assert_raise Fluffy.OperationError, ~r/evaluate.*[Tt]imeout/s, fn ->
        Playwright.evaluate(session, by_css("#missing"), "element => element.id", timeout: 100)
      end

      assert_raise Fluffy.OperationError, ~r/strict mode/, fn ->
        Playwright.evaluate(session, by_css("li"), "element => element.id", timeout: 1_000)
      end
    end

    test "evaluate_all sees every element, or none", %{session: session} do
      assert Playwright.evaluate_all(session, by_css("li"), "items => items.map(item => item.id)") == ["one", "two"]
      assert Playwright.evaluate_all(session, by_css("li"), "(items, arg) => items.length + arg", 1) == 3
      assert Playwright.evaluate_all(session, by_css("li"), "(_, arg) => arg", [], timeout: 1_000) == []
      assert Playwright.evaluate_all(session, by_css("li"), "items => items.length", timeout: 1_000) == 2
      assert Playwright.evaluate_all(session, by_css("#missing"), "items => items.length") == 0
    end

    test "evaluate_all is bounded and validates options", %{session: session} do
      assert_raise Fluffy.OperationError, ~r/evaluate_all.*[Tt]imeout/s, fn ->
        Playwright.evaluate_all(session, by_css("li"), "() => new Promise(() => {})", timeout: 100)
      end

      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:signal/, fn ->
        Playwright.evaluate_all(session, by_css("li"), "items => items.length", signal: :none)
      end
    end

    test "wait_for_function on a locator waits and returns the session", %{session: session} do
      Playwright.evaluate(
        session,
        "setTimeout(() => { document.querySelector('#one').dataset.ready = 'yes' }, 100); true"
      )

      one = by_css("#one")

      assert Playwright.wait_for_function(session, one, "element => element.dataset.ready === 'yes'") == session
      assert Playwright.wait_for_function(session, one, "(element, n) => element.dataset.n === n", "1") == session
      assert Playwright.wait_for_function(session, one, "element => element.id === 'one'", timeout: 1_000) == session
    end

    test "wait_for_function on a locator is bounded", %{session: session} do
      assert_raise Fluffy.OperationError, ~r/wait_for_function.*[Tt]imeout/s, fn ->
        Playwright.wait_for_function(session, by_css("#one"), "() => false", timeout: 100)
      end
    end
  end

  describe "all" do
    test "returns one locator per current match, usable on its own" do
      session = session_for_html(:playwright, "<ul><li>One</li><li>Two</li></ul>")

      assert [first, second] = Playwright.all(session, by_css("li"))
      assert %Fluffy.Locator{} = first

      session
      |> expect(to_have_text(first, "One"))
      |> expect(to_have_text(second, "Two"))
    end

    test "does not wait, and returns [] without a match" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert Playwright.all(session, by_css("li")) == []
    end
  end

  describe "drop" do
    test "drops data on the target and returns the session" do
      session =
        session_for_html(:playwright, ~s|<div id="zone" style="width: 100px; height: 100px">Empty</div>|)

      zone = by_css("#zone")

      Playwright.evaluate(session, zone, """
      zone => {
        zone.addEventListener("dragover", event => event.preventDefault());
        zone.addEventListener("drop", event => {
          event.preventDefault();
          zone.textContent = event.dataTransfer.getData("text/plain");
        });
      }
      """)

      assert Playwright.drop(session, zone, %{data: %{"text/plain" => "dropped"}}) == session
      expect(session, to_have_text(zone, "dropped"))
    end

    test "is bounded" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert_raise Fluffy.OperationError, ~r/drop.*[Tt]imeout/s, fn ->
        Playwright.drop(session, by_css("#missing"), %{data: %{"text/plain" => "x"}}, timeout: 100)
      end
    end
  end

  describe "waits when the page closes" do
    test "wait_for on a locator raises" do
      popup = closing_popup("<p>Harness</p>")

      assert_raise Fluffy.OperationError, ~r/wait_for.*closed/is, fn ->
        wait_for(popup, by_css("#never"), timeout: 10_000)
      end
    end

    test "wait_for_load_state raises" do
      popup = closing_popup("<p>Harness</p>", "setInterval(() => fetch(location.href), 100)")

      assert_raise Fluffy.OperationError, ~r/wait_for_load_state.*closed/is, fn ->
        Playwright.wait_for_load_state(popup, :networkidle, timeout: 10_000)
      end
    end

    # Only Fluffy's LiveView readiness check reads this root's view, so the page
    # closes exactly while Fluffy adopts its document.
    @closes_on_adoption """
    <div id="root" data-phx-main></div>
    <script>
      document.getElementById('root').phxPrivate = {get view() { setTimeout(() => window.close()) }}
    </script>
    """

    test "a page closing while Fluffy adopts it fails the operation" do
      for {operation, call} <- [
            wait_for: &wait_for(&1, by_css("#never"), timeout: 10_000),
            click: &click(&1, by_css("#never"), timeout: 10_000),
            evaluate_all: &Playwright.evaluate_all(&1, by_css("#never"), "() => 1")
          ] do
        popup = popup_showing(@closes_on_adoption)
        assert_raise Fluffy.OperationError, ~r/#{operation}.*closed/is, fn -> call.(popup) end
      end
    end

    test "a page closing while Fluffy adopts it fails an expectation" do
      popup = popup_showing(@closes_on_adoption)

      assert_raise ExUnit.AssertionError, ~r/closed/i, fn ->
        expect(popup, to_be_visible(by_css("#never")), timeout: 10_000)
      end
    end

    test "a page closing while Fluffy adopts it fails unwrap and clock calls" do
      for {operation, call} <- [
            unwrap: &unwrap(&1, fn _page -> :ok end),
            "Clock.install": &Fluffy.Playwright.Clock.install/1
          ] do
        popup = popup_showing(@closes_on_adoption)
        error = assert_raise Fluffy.OperationError, fn -> call.(popup) end
        assert %Fluffy.OperationError{operation: ^operation, cause: %PlaywrightEx.TargetClosedError{}} = error
      end
    end

    test "an action navigating to a page that closes while Fluffy adopts it succeeds" do
      closing = TestHTTPFixtures.register(%{body: @closes_on_adoption})
      popup = popup_showing(~s|<a href="#{TestHTTPFixtures.path(closing)}">Next</a>|)

      assert %Fluffy.Session{} = click(popup, by_role(:link, name: "Next"))
    end

    # Like @closes_on_adoption, but only when the document was reached by the
    # navigation type named in `?close=`.
    @closes_on_navigation """
    <div id="root" data-phx-main></div>
    <script>
      const want = new URLSearchParams(location.search).get('close')
      let type = performance.getEntriesByType('navigation')[0].type
      addEventListener('pageshow', e => { if (e.persisted) type = 'back_forward' })
      const root = document.getElementById('root')
      root.phxPrivate = {get view() { if (type === want) setTimeout(() => window.close()); else root.classList.add('phx-connected') }}
    </script>
    """

    test "a page closing while Fluffy adopts a navigation fails visit, reload and history navigation" do
      closing = TestHTTPFixtures.register(%{body: @closes_on_navigation})
      plain = TestHTTPFixtures.path(TestHTTPFixtures.register(%{body: "<p>Plain</p>"}))
      closes_on = &TestHTTPFixtures.path(closing, "?close=#{&1}")

      for {operation, call} <- [
            visit: &visit(&1, closes_on.("navigate")),
            reload: &(&1 |> visit(closes_on.("reload")) |> reload()),
            go_back: &(&1 |> visit(closes_on.("back_forward")) |> visit(plain) |> Playwright.go_back()),
            go_forward: &(&1 |> visit(closes_on.("back_forward")) |> Playwright.go_back() |> Playwright.go_forward())
          ] do
        popup = popup_showing("<p>Start</p>")
        error = assert_raise Fluffy.OperationError, fn -> call.(popup) end
        assert %Fluffy.OperationError{operation: ^operation, cause: %PlaywrightEx.TargetClosedError{}} = error
      end
    end
  end

  describe "unroute_all when Playwright does not finish" do
    setup do
      fixture = TestHTTPFixtures.register(fn _request -> %{body: "server"} end)
      session = start_session(:playwright)
      visit(session, TestHTTPFixtures.path(fixture, "/page"))
      [session: session, url: TestHTTPFixtures.url(fixture, "/api")]
    end

    test "releases the routes even when Playwright does not finish", %{session: session} do
      Playwright.route(session, "**/api", fn route -> Route.fulfill(route, body: "routed") end)

      session = put_session_timeout(session, 1_000)

      # A frozen page holds up unroute_all on some browsers.
      assert_raise PlaywrightEx.TimeoutError, ~r/Timeout 1000ms exceeded during evaluate/, fn ->
        Playwright.evaluate(session, "() => { while (true) {} }")
      end

      try do
        Playwright.unroute_all(session)
      rescue
        error in PlaywrightEx.TimeoutError -> assert error.message =~ "Timeout 1000ms exceeded during unroute_all"
      end

      {:ok, resources} = Fluffy.SessionRuntime.resources(session.runtime)
      assert Enum.filter(resources, &(elem(&1, 0) == :route)) == []
    end
  end

  describe "Route.fetch" do
    test "returns the real response, usable with fulfill" do
      fixture = TestHTTPFixtures.register(fn _request -> %{body: "server"} end)
      session = start_session(:playwright)
      visit(session, TestHTTPFixtures.path(fixture, "/page"))

      Playwright.route(session, "**/api", fn route ->
        # Firefox offers zstd, whose bodies Playwright's fetch hands back still compressed.
        response = Route.fetch(route, headers: %{"accept-encoding" => "identity"})
        Route.fulfill(route, response: response, status: 201)
      end)

      assert Playwright.evaluate(
               session,
               "url => fetch(url).then(async r => r.status + ':' + (await r.text()))",
               TestHTTPFixtures.url(fixture, "/api")
             ) == "201:server"
    end

    test "timeout: 0 gives up at once instead of waiting without limit" do
      fixture =
        TestHTTPFixtures.register(fn _request ->
          Process.sleep(500)
          %{body: "server"}
        end)

      session = start_session(:playwright)
      visit(session, TestHTTPFixtures.path(fixture, "/page"))
      owner = self()

      Playwright.route(session, "**/api", fn route ->
        send(owner, {:fetch, catch_error(Route.fetch(route, timeout: 0))})
        Route.fulfill(route, body: "routed")
      end)

      assert Playwright.evaluate(session, "url => fetch(url).then(r => r.text())", TestHTTPFixtures.url(fixture, "/api")) ==
               "routed"

      assert_receive {:fetch, %PlaywrightEx.TimeoutError{}}
    end
  end

  describe "page output" do
    test "content returns the page's HTML" do
      session = session_for_html(:playwright, "<p id='here'>Harness</p>")

      assert Playwright.content(session) =~ "Harness"
      assert Playwright.content(session, timeout: 1_000) =~ ~s(id="here")
    end

    test "title returns the page's title" do
      session = session_for_html(:playwright, "<p>Harness</p>")
      Playwright.evaluate(session, "document.title = 'A title'")

      assert Playwright.title(session) == "A title"
      assert Playwright.title(session, timeout: 1_000) == "A title"
    end

    test "bring_to_front returns the session" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert Playwright.bring_to_front(session) == session
      assert Playwright.bring_to_front(session, timeout: 1_000) == session
    end

    @tag :tmp_dir
    @tag skip: if(not playwright_engine?(:chromium), do: "only Chromium prints PDFs")
    test "pdf saves the page and returns the session", %{tmp_dir: tmp_dir} do
      session = session_for_html(:playwright, "<p>Harness</p>")
      path = Path.join([tmp_dir, "nested", "page.pdf"])

      assert Playwright.pdf(session, path, landscape: true, timeout: 5_000) == session
      assert <<"%PDF", _rest::binary>> = File.read!(path)
    end

    test "rejects unknown options" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      for call <- [
            fn -> Playwright.content(session, signal: :none) end,
            fn -> Playwright.title(session, signal: :none) end,
            fn -> Playwright.bring_to_front(session, signal: :none) end,
            fn -> Playwright.pdf(session, "/tmp/fluffy-never-written.pdf", signal: :none) end
          ] do
        assert_raise NimbleOptions.ValidationError, call
      end
    end
  end

  describe "storage" do
    test "local_storage and session_storage read the page's origin" do
      session = session_for_html(:playwright, "<p>Harness</p>")
      Playwright.evaluate(session, "localStorage.setItem('l', '1'); sessionStorage.setItem('s', '2')")

      assert Playwright.local_storage(session) == [%{name: "l", value: "1"}]
      assert Playwright.session_storage(session, timeout: 1_000) == [%{name: "s", value: "2"}]
    end

    test "set_storage_state replaces storage with a saved state" do
      session = session_for_html(:playwright, "<p>Harness</p>")
      Playwright.evaluate(session, "localStorage.setItem('kept', 'yes')")
      state = Playwright.storage_state(session)
      Playwright.evaluate(session, "localStorage.clear(); localStorage.setItem('other', 'x')")

      assert Playwright.set_storage_state(session, state) == session
      assert Playwright.local_storage(session) == [%{name: "kept", value: "yes"}]
    end
  end

  describe "bounding_box" do
    test "returns the box, and nil for an element without one" do
      html =
        ~s(<div id="box" style="position: fixed; left: 10px; top: 20px; width: 30px; height: 40px"></div>
           <div id="hidden" style="display: none"></div>)

      session = session_for_html(:playwright, html)

      assert %{x: x, y: y, width: width, height: height} = Playwright.bounding_box(session, by_css("#box"))
      assert {x, y, width, height} == {10, 20, 30, 40}
      assert Playwright.bounding_box(session, by_css("#hidden"), timeout: 1_000) == nil
    end

    test "raises for a missing locator and rejects unknown options" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert_raise Fluffy.OperationError, ~r/bounding_box.*[Tt]imeout/s, fn ->
        Playwright.bounding_box(session, by_css("#missing"), timeout: 100)
      end

      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:signal/, fn ->
        Playwright.bounding_box(session, by_css("p"), signal: :none)
      end
    end
  end

  describe "unroute_all" do
    @fetch "url => fetch(url).then(response => response.text())"

    test "removes every route, which unroute and route can then follow" do
      fixture = TestHTTPFixtures.register(fn _request -> %{body: "server"} end)
      session = start_session(:playwright)
      visit(session, TestHTTPFixtures.path(fixture, "/page"))
      url = TestHTTPFixtures.url(fixture, "/api")
      other = TestHTTPFixtures.url(fixture, "/other")
      handler = fn route -> Route.fulfill(route, body: "routed") end

      session = session |> Playwright.route("**/api", handler) |> Playwright.route("**/other", handler)
      assert Playwright.evaluate(session, @fetch, url) == "routed"

      assert Playwright.unroute_all(session) == session
      assert Playwright.evaluate(session, @fetch, url) == "server"
      assert Playwright.evaluate(session, @fetch, other) == "server"

      assert Playwright.unroute(session, "**/api") == session
      Playwright.route(session, "**/api", handler)
      assert Playwright.evaluate(session, @fetch, url) == "routed"
    end

    test "works without routes and rejects unknown options" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert Playwright.unroute_all(session) == session

      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:signal/, fn ->
        Playwright.unroute_all(session, signal: :none)
      end
    end
  end

  for driver <- [:static, :live] do
    @tag driver: driver
    test "the assertions require a browser with #{driver}" do
      session =
        case unquote(driver) do
          :static -> session_for_html(:static, "<p>Top</p>")
          :live -> :phoenix |> start_session() |> visit("/live/potions")
        end

      p = by_css("p")

      for expectation <- [
            to_have_css(p, "color", "red"),
            not_(to_have_css(p, "color", "red")),
            to_have_js_property(p, "value", "x"),
            to_have_screenshot(p, path: "x.png"),
            page_to_have_screenshot(path: "x.png"),
            to_have_role(p, :paragraph),
            to_have_accessible_name(p, "x"),
            to_have_accessible_description(p, "x"),
            to_have_accessible_error_message(p, "x"),
            to_match_aria_snapshot(p, "- paragraph"),
            page_to_match_aria_snapshot("- paragraph")
          ] do
        error = assert_raise Fluffy.CapabilityError, fn -> expect(session, expectation) end
        assert error.driver == unquote(driver)
        assert Fluffy.Capability.status(error.capability, unquote(driver)) == :browser_only
      end
    end
  end

  @tag driver: :static
  test "the browser functions reject Phoenix sessions" do
    session = start_session(:phoenix)
    p = by_css("p")

    for operation <- [
          fn -> Playwright.evaluate(session, "1", timeout: 100) end,
          fn -> Playwright.wait_for_function(session, "true", timeout: 100) end,
          fn -> Playwright.set_extra_http_headers(session, %{"x-a" => "1"}) end,
          fn -> Playwright.add_script_tag(session, content: "1") end,
          fn -> Playwright.add_style_tag(session, content: "p {}") end,
          fn -> Playwright.wait_for_load_state(session) end,
          fn -> Playwright.unroute_all(session) end,
          fn -> wait_for(session, p) end,
          fn -> Playwright.evaluate(session, p, "1") end,
          fn -> Playwright.evaluate_all(session, p, "1") end,
          fn -> Playwright.wait_for_function(session, p, "true") end,
          fn -> Playwright.all(session, p) end,
          fn -> Playwright.drop(session, p, %{data: %{"text/plain" => "x"}}) end,
          fn -> Playwright.pdf(session, "/tmp/fluffy-never-written.pdf") end,
          fn -> Playwright.bring_to_front(session) end,
          fn -> Playwright.content(session) end,
          fn -> Playwright.title(session) end,
          fn -> Playwright.set_storage_state(session, %{}) end,
          fn -> Playwright.local_storage(session) end,
          fn -> Playwright.session_storage(session) end,
          fn -> Playwright.bounding_box(session, p) end,
          fn -> Playwright.aria_snapshot(session) end,
          fn -> Playwright.aria_snapshot(session, p) end,
          fn -> Playwright.viewport_size(session) end
        ] do
      assert_raise Fluffy.CapabilityError, operation
    end
  end

  # A popup whose `body` has loaded, not yet adopted by any Fluffy action.
  defp popup_showing(body) do
    ready = "<script>window.opener.postMessage('ready', '*')</script>"
    fixture = TestHTTPFixtures.register(%{body: body <> ready})
    session = session_for_html(:playwright, "<p>Opener</p>")
    pending = wait_for(session, Fluffy.Event.popup())

    Playwright.evaluate(
      session,
      "url => new Promise(resolve => { window.addEventListener('message', resolve); window.open(url) }).then(() => true)",
      TestHTTPFixtures.path(fixture)
    )

    Playwright.switch_page(session, await(pending))
  end

  # A popup showing `html` that closes itself soon, which its opener's page does not allow.
  defp closing_popup(html, script \\ "1") do
    session = session_for_html(:playwright, "<p>Opener</p>")
    pending = wait_for(session, Fluffy.Event.popup())
    Playwright.evaluate(session, "window.open('/harness'); true")
    popup = Playwright.switch_page(session, await(pending))

    Playwright.evaluate(popup, """
    document.body.innerHTML = #{JSON.encode!(html)}
    #{script}
    true
    """)

    # Adopted first, so the close races only the wait under test.
    popup = wait_for(popup, by_css("body"), state: :attached)
    Playwright.evaluate(popup, "setTimeout(() => window.close(), 500); true")
    popup
  end
end
