defmodule Fluffy.Conformance.BrowserAPITest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Playwright

  @tag driver: :playwright
  test "creates named pages sharing cookies, switches, and closes resources" do
    session = start_session(:playwright)
    session = Playwright.add_cookies(session, [%{name: "token", value: "abc", url: Fluffy.TestServer.base_url()}])
    other = new_page(session, :other)
    assert Enum.sort(page_names(other)) == [:main, :other]
    assert Playwright.evaluate(other, "document.visibilityState") == "visible"
    assert_raise ArgumentError, ~r/already in use/, fn -> new_page(other, :other) end
    other = visit(other, "/harness")
    assert Playwright.evaluate(other, "document.cookie") =~ "token=abc"
    main = switch_page(other, :main)
    assert Playwright.evaluate(main, "document.visibilityState") == "visible"
    assert page_names(close_page(main, :other)) == [:main]
    assert :ok = close_session(main)
  end

  @tag driver: :playwright
  test "navigates history and handles an empty history" do
    session = :playwright |> start_session() |> go_back() |> go_forward()
    session = session |> visit("/harness") |> visit("/chamber")
    session = session |> go_back() |> expect(page_to_have_url(Fluffy.TestServer.base_url() <> "/harness"))
    session |> go_forward() |> expect(page_to_have_url(Fluffy.TestServer.base_url() <> "/chamber"))
  end

  @tag driver: :playwright
  test "exports and restores storage and filters cookies" do
    session = :playwright |> start_session() |> visit("/harness")

    session =
      Playwright.add_cookies(session, [
        %{name: "keep", value: "yes", url: Fluffy.TestServer.base_url()},
        %{name: "drop", value: "no", url: Fluffy.TestServer.base_url()}
      ])

    Playwright.evaluate(session, "localStorage.setItem('saved', 'value')")
    session = Playwright.clear_cookies(session, name: ~r/^drop$/)
    assert Enum.map(Playwright.cookies(session), & &1.name) == ["keep"]
    path = Path.join(System.tmp_dir!(), "fluffy-storage-#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(path) end)
    state = Playwright.storage_state(session, path: path)
    assert Jason.decode!(File.read!(path)) == Jason.decode!(Jason.encode!(state))
    restored = :playwright |> start_session(browser_context: [storage_state: state]) |> visit("/harness")
    assert Playwright.evaluate(restored, "localStorage.getItem('saved')") == "value"
    assert Playwright.evaluate(restored, "document.cookie") =~ "keep=yes"
    from_file = :playwright |> start_session(browser_context: [storage_state: path]) |> visit("/harness")
    assert Playwright.evaluate(from_file, "localStorage.getItem('saved')") == "value"
    assert Playwright.cookies(Playwright.clear_cookies(session)) == []
  end

  @tag driver: :playwright
  test "hover, drag, and typing emit native browser events" do
    session =
      Fluffy.session_for_html(:playwright, """
      <button onmouseover="this.textContent='Hovered'">Hover me</button>
      <input aria-label="Text" onkeydown="window.keys=(window.keys||0)+1">
      <div draggable="true" id="source">Drag me</div>
      <div id="target" style="margin-top:40px;width:200px;height:100px" ondragover="event.preventDefault()" ondrop="this.textContent='Dropped'">Target</div>
      """)

    session = session |> hover(by_role(:button)) |> expect("Hovered" |> by_text() |> to_be_visible())
    session = press_sequentially(session, by_label("Text"), "abc", delay: 1)
    assert Playwright.evaluate(session, "window.keys") == 3

    session
    |> expect("Text" |> by_label() |> to_have_value("abc"))
    |> drag_to(by_css("#source"), by_css("#target"))
    |> expect("Dropped" |> by_text() |> to_be_visible())
  end

  @tag driver: :playwright
  test "typing is strict and reconciles navigation" do
    session = Fluffy.session_for_html(:playwright, "<input><input>")
    error = assert_raise Fluffy.OperationError, fn -> press_sequentially(session, by_css("input"), "x", timeout: 100) end
    assert error.operation == :press_sequentially
    session = Fluffy.set_html(session, ~s(<input oninput="location.href='/chamber'">))

    session
    |> press_sequentially(by_css("input"), "x")
    |> expect(page_to_have_url(Fluffy.TestServer.base_url() <> "/chamber"))
  end

  @tag driver: :playwright
  test "history reconciles same-document navigation and leaves an empty history unchanged" do
    session = :playwright |> start_session() |> new_page(:blank)
    assert go_back(session) == session
    assert go_forward(session) == session
    session = session |> visit("/harness") |> visit("/harness#other")
    session = session |> go_back() |> expect(page_to_have_url(Fluffy.TestServer.base_url() <> "/harness"))
    session |> go_forward() |> expect(page_to_have_url(Fluffy.TestServer.base_url() <> "/harness#other"))
  end

  test "browser operations reject Phoenix sessions" do
    session = start_session(:phoenix)

    for operation <- [
          fn -> new_page(session, :other) end,
          fn -> go_back(session) end,
          fn -> go_forward(session) end,
          fn -> hover(session, by_css("button")) end,
          fn -> drag_to(session, by_css("a"), by_css("b")) end,
          fn -> press_sequentially(session, by_css("input"), "abc") end,
          fn -> Playwright.cookies(session) end,
          fn -> Playwright.add_cookies(session, []) end,
          fn -> Playwright.clear_cookies(session) end,
          fn -> Playwright.storage_state(session) end
        ] do
      assert_raise Fluffy.CapabilityError, operation
    end

    assert :ok = close_session(session)
  end
end
