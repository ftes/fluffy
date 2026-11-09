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

      assert_raise RuntimeError, ~r/evaluate did not finish within 100ms/, fn ->
        Playwright.evaluate(session, "new Promise(() => {})", timeout: 100)
      end

      assert_raise RuntimeError, ~r/evaluate did not finish within 100ms/, fn ->
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
        expect(session, to_have_screenshot(box, path: path, timeout: 500))
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
        expect(session, not_(to_have_screenshot(box, path: path, timeout: 500)))
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
        expect(session, page_to_have_screenshot(path: path, timeout: 500))
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
             |> Playwright.wait_for(by_css("#late"), [])
             |> Playwright.wait_for(by_css("#gone"), state: :detached)
             |> Playwright.wait_for(by_css("#hidden"), state: :hidden)
             |> Playwright.wait_for(by_css("#here"), state: :attached) == session
    end

    test "is bounded by timeout: and the session's timeout:" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert_raise Fluffy.OperationError, ~r/wait_for.*[Tt]imeout/s, fn ->
        Playwright.wait_for(session, by_css("#missing"), timeout: 100)
      end

      bounded = session_for_html(:playwright, "<p>Harness</p>", timeout: 300)
      started = System.monotonic_time(:millisecond)

      assert_raise Fluffy.OperationError, ~r/wait_for.*[Tt]imeout/s, fn ->
        Playwright.wait_for(bounded, by_css("#missing"), [])
      end

      assert System.monotonic_time(:millisecond) - started < 5_000
    end

    test "rejects unknown options" do
      session = session_for_html(:playwright, "<p>Harness</p>")

      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:signal/, fn ->
        Playwright.wait_for(session, by_css("p"), signal: :none)
      end
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

      assert Playwright.unroute_all(session, behavior: :ignore_errors) == session
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
          fn -> Playwright.wait_for(session, p, []) end,
          fn -> Playwright.bounding_box(session, p) end,
          fn -> Playwright.aria_snapshot(session) end,
          fn -> Playwright.aria_snapshot(session, p) end,
          fn -> Playwright.viewport_size(session) end
        ] do
      assert_raise Fluffy.CapabilityError, operation
    end
  end
end
