defmodule Fluffy.Conformance.UnwrapTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright
  import Phoenix.ConnTest, only: [get: 2]

  alias Fluffy.Event
  alias Fluffy.Page
  alias Fluffy.Session
  alias Fluffy.TestHTTPFixtures
  alias Fluffy.TestWeb.Endpoint
  alias Phoenix.LiveViewTest.View
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Locator, as: BrowserLocator
  alias PlaywrightEx.Page, as: BrowserPage

  @endpoint Endpoint

  test "rejects unwrap before the Phoenix backend has visited and classified a page" do
    session = start_test_session(:phoenix)
    Process.put(:unwrap_callback_ran, false)

    assert_raise ArgumentError, ~r/unwrap.*before.*visit/i, fn ->
      unwrap(session, fn _native ->
        Process.put(:unwrap_callback_ran, true)
      end)
    end

    refute Process.get(:unwrap_callback_ran)
  end

  for driver <- [:static, :live] do
    @tag driver: driver
    test "rejects a native locator with #{driver}" do
      path = if unquote(driver) == :static, do: "/chamber", else: "/live/nested"
      session = :phoenix |> start_test_session() |> visit(path)

      assert_raise Fluffy.CapabilityError, ~r/:native_locator requires a Playwright session/, fn ->
        unwrap(session, by_css("body"), fn _locator -> flunk("callback ran") end)
      end
    end
  end

  describe "Static" do
    test "a LiveView page kept by a no-content response passes that response's conn" do
      fixture = TestHTTPFixtures.register(%{status: 204})

      :phoenix
      |> start_test_session()
      |> visit("/live/no-content?" <> URI.encode_query(to: TestHTTPFixtures.path(fixture, "/save")))
      |> submit(by_css("#http-form"))
      |> unwrap(fn %Plug.Conn{status: 204} = conn -> get(conn, "/chamber") end)
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    test "accepts the unchanged current conn and remains pipeable" do
      session = start_test_session(:phoenix)

      session
      |> visit("/chamber")
      |> unwrap(fn %Plug.Conn{} = conn -> conn end)
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    test "passes the current conn, requires its replacement, and reconciles response state" do
      session = start_test_session(:phoenix)

      session =
        session
        |> visit("/chamber")
        |> unwrap(fn %Plug.Conn{request_path: "/chamber"} = conn ->
          %{
            conn
            | status: 202,
              resp_body: "<!doctype html><html><body><p>Native replacement</p></body></html>"
          }
        end)
        |> expect("Native replacement" |> by_text() |> to_be_visible())

      assert Session.page_state(session).conn.status == 202
    end

    test "rejects a callback result that is not a Plug.Conn" do
      session = :phoenix |> start_test_session() |> visit("/chamber")

      assert_raise ArgumentError, ~r/Static unwrap callback must return.*Plug.Conn/s, fn ->
        unwrap(session, fn _conn -> :ignored end)
      end
    end

    test "follows a returned conn redirect and reclassifies its Secret chamber" do
      test_pid = self()
      session = start_test_session(:phoenix)

      session =
        session
        |> visit("/chamber")
        |> unwrap(fn conn ->
          conn = get(conn, "/session/start?identity=Native")
          [set_cookie] = Plug.Conn.get_resp_header(conn, "set-cookie")
          assert set_cookie =~ "_fluffy_test="
          conn
        end)
        |> expect(Fluffy.Expect.page_to_have_url("/live/session"))
        |> expect("Live identity: Native" |> by_text() |> to_be_visible())
        |> unwrap(fn %View{} -> send(test_pid, :unwrapped_live_destination) end)

      assert Session.current_driver(session) == :live
      assert_receive :unwrapped_live_destination
    end

    test "propagates callback exceptions, throws, and exits unchanged" do
      session = :phoenix |> start_test_session() |> visit("/chamber")

      assert_raise RuntimeError, "native exception", fn ->
        unwrap(session, fn _conn -> raise "native exception" end)
      end

      assert catch_throw(unwrap(session, fn _conn -> throw(:native_throw) end)) == :native_throw
      assert catch_exit(unwrap(session, fn _conn -> exit(:native_exit) end)) == :native_exit
    end
  end

  describe "Live" do
    test "passes the current View, ignores the callback result, and re-renders" do
      test_pid = self()
      session = start_test_session(:phoenix)

      session =
        session
        |> visit("/live/three-heads")
        |> unwrap(fn %View{} = view ->
          send(test_pid, {:native_view, view})
          _html = Phoenix.LiveViewTest.render_click(view, "increment")
          {:ok, :not_a_view, :discarded_metadata}
        end)
        |> expect("Sleeping heads: 1" |> by_text() |> to_be_visible())

      assert_receive {:native_view, %View{} = view}
      assert Session.page_state(session).view == view
    end

    test "allows an assertion-only callback without making its result driver state" do
      session = :phoenix |> start_test_session() |> visit("/live/three-heads")

      session
      |> unwrap(fn view ->
        assert Phoenix.LiveViewTest.render(view) =~ "Sleeping heads: 0"
      end)
      |> expect("Sleeping heads: 0" |> by_text() |> to_be_visible())
    end

    test "reconciles the retained View instead of a stale rendered return value" do
      session = :phoenix |> start_test_session() |> visit("/live/three-heads")

      session
      |> unwrap(fn view ->
        stale_html = Phoenix.LiveViewTest.render(view)
        _latest_html = Phoenix.LiveViewTest.render_click(view, "increment")
        stale_html
      end)
      |> expect("Sleeping heads: 1" |> by_text() |> to_be_visible())
    end

    test "commits a native patch without requiring the callback to return the View" do
      session = start_test_session(:phoenix)

      session
      |> visit("/live/chamber-map")
      |> unwrap(fn view ->
        _html = Phoenix.LiveViewTest.render_patch(view, "/live/chamber-map?step=native")
        :ignored
      end)
      |> expect(Fluffy.Expect.page_to_have_url("/live/chamber-map?step=native"))
      |> expect("Map position: native" |> by_text() |> to_be_visible())
    end

    test "reconciles a native hook event and a queued Live render" do
      session = start_test_session(:phoenix)

      session
      |> visit("/live/async?delay=10000")
      |> unwrap(fn view ->
        send(view.pid, :ready)
        :ignored
      end)
      |> expect("Status: ready" |> by_text() |> to_be_visible())
      |> unwrap(fn view ->
        _html = Phoenix.LiveViewTest.render_hook(view, "activate", %{})
        :ignored
      end)
      |> expect("Activated" |> by_text() |> to_be_visible())
    end

    test "follows native Live navigation through normal page classification" do
      session = start_test_session(:phoenix)

      session =
        session
        |> visit("/live/chamber-map")
        |> unwrap(fn view ->
          view
          |> Phoenix.LiveViewTest.element("a", "Secret chamber")
          |> Phoenix.LiveViewTest.render_click()

          :ignored
        end)
        |> expect(Fluffy.Expect.page_to_have_url("/live/secret-chamber"))
        |> expect("The secret chamber is open" |> by_text() |> to_be_visible())

      assert Session.current_driver(session) == :live
    end

    test "commits phx-trigger-action as an HTTP navigation after a native submit" do
      session = start_test_session(:phoenix)

      session =
        session
        |> visit("/live/potions")
        |> unwrap(fn view ->
          _html = Phoenix.LiveViewTest.render_submit(view, "save", %{"commit" => "trigger"})
          :ignored
        end)
        |> expect("The guardian sleeps" |> by_text() |> to_be_visible())

      assert Session.current_driver(session) == :static
    end

    test "follows a native redirect after discarding the render result" do
      session = start_test_session(:phoenix)

      session =
        session
        |> visit("/live/chamber-map")
        |> unwrap(fn view ->
          _redirect = Phoenix.LiveViewTest.render_click(view, "redirect_static")
          :ignored
        end)
        |> expect(Fluffy.Expect.page_to_have_url("/chamber"))
        |> expect("The guardian sleeps" |> by_text() |> to_be_visible())

      assert Session.current_driver(session) == :static
    end

    test "preserves flash from a native Live redirect" do
      session = start_test_session(:phoenix)

      session
      |> visit("/live/chamber-map")
      |> unwrap(fn view ->
        _redirect = Phoenix.LiveViewTest.render_click(view, "redirect_with_flash")
        :ignored
      end)
      |> expect(Fluffy.Expect.page_to_have_url("/live/secret-chamber"))
      |> expect("The secret passage opened" |> by_text() |> to_be_visible())
    end

    test "does not translate an exit raised by the native callback" do
      session = :phoenix |> start_test_session() |> visit("/live/three-heads")

      reason =
        catch_exit(unwrap(session, fn %View{} -> exit(:native_crash) end))

      assert reason == :native_crash
    end

    test "propagates callback exceptions and throws unchanged" do
      session = :phoenix |> start_test_session() |> visit("/live/three-heads")

      assert_raise RuntimeError, "native Live exception", fn ->
        unwrap(session, fn %View{} -> raise "native Live exception" end)
      end

      assert catch_throw(unwrap(session, fn %View{} -> throw(:native_live_throw) end)) ==
               :native_live_throw
    end
  end

  describe "Playwright" do
    @tag driver: :playwright
    test "passes the native page and ignores the callback's return value" do
      test_pid = self()
      session = playwright_html("<p id=target>Before</p>")

      session =
        session
        |> unwrap(fn %BrowserPage{} = page ->
          BrowserPage.evaluate!(page, "document.querySelector('#target').textContent = 'After'")
          send(test_pid, {:native_page, page})
          :discarded_return_value
        end)
        |> expect("After" |> by_text() |> to_be_visible())

      assert_receive {:native_page, page}
      assert Session.page_state(session).page == page
    end

    @tag driver: :playwright
    test "reaches the BrowserContext through the page" do
      test_pid = self()
      session = playwright_html("<p>Context operation</p>")

      session
      |> unwrap(fn page ->
        :ok = BrowserPage.bring_to_front(page)
        send(test_pid, {:cookies, page |> BrowserPage.context() |> BrowserContext.cookies!()})
        {:error, :ignored_native_result}
      end)
      |> expect("Context operation" |> by_text() |> to_be_visible())

      assert_receive {:cookies, cookies}
      assert is_list(cookies)
    end

    @tag driver: :playwright
    test "leaves native error tuples to the callback" do
      session = playwright_html("<p>Still usable</p>")

      session
      |> unwrap(fn page ->
        assert {:error, %PlaywrightEx.TimeoutError{}} =
                 BrowserPage.wait_for_selector(page, "#does-not-exist", timeout: 1)
      end)
      |> expect("Still usable" |> by_text() |> to_be_visible())
    end

    @tag driver: :playwright
    test "preserves document identity across a native same-frame URL change" do
      session = playwright_html("<p>Hash destination</p>")
      before_document = Session.current_page(session).document_id

      session =
        session
        |> unwrap(fn page -> BrowserPage.evaluate!(page, "location.hash = 'native'") end)
        |> expect(Fluffy.Expect.page_to_have_url("/harness#native"))

      assert Session.current_page(session).document_id == before_document
    end

    @tag driver: :playwright
    test "synchronizes a native full document navigation" do
      session = playwright_html("<p>Before navigation</p>")

      session
      |> unwrap(fn page -> BrowserPage.goto!(page, "/chamber") end)
      |> expect(Fluffy.Expect.page_to_have_url("/chamber"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    @tag driver: :playwright
    test "composes native navigation with page assertions" do
      "<p>Before navigation</p>"
      |> playwright_html()
      |> unwrap(fn page -> BrowserPage.goto!(page, "/chamber") end)
      |> expect(Fluffy.Expect.page_to_have_url("/chamber"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    @tag driver: :playwright
    test "adopts a document navigated natively outside unwrap before the next action" do
      session = playwright_html("<p>Before navigation</p>")
      page = Session.page_state(session).page
      BrowserPage.goto!(page, "/chamber")

      session
      |> expect(Fluffy.Expect.page_to_have_url("/chamber"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    @tag driver: :playwright
    test "composes with a pre-armed page expectation" do
      session = playwright_html("<p>Main page</p>")

      pending = wait_for(session, Event.page())

      unwrap(session, fn page ->
        page |> BrowserPage.context() |> BrowserContext.new_page!() |> BrowserPage.goto!("/chamber")
      end)

      child = await(pending)

      session
      |> switch_page(child)
      |> expect(Fluffy.Expect.page_to_have_url(Fluffy.TestServer.base_url() <> "/chamber"))
      |> expect(Fluffy.Expect.page_to_have_opener(nil))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    @tag driver: :playwright
    test "captures a blank page without requiring an HTTP response" do
      session = playwright_html("<p>Main page</p>")

      pending = wait_for(session, Event.page())
      unwrap(session, fn page -> page |> BrowserPage.context() |> BrowserContext.new_page!() end)
      child = await(pending)

      assert Page.url(child) == "about:blank"

      session
      |> switch_page(child)
      |> expect(Fluffy.Expect.page_to_have_url("about:blank"))
    end

    @tag driver: :playwright
    test "reports invalidation when native code closes the tracked page" do
      session = playwright_html("<p>Tracked page</p>")

      assert_raise ArgumentError, ~r/unwrap.*invalidated.*page/i, fn ->
        unwrap(session, &BrowserPage.close!/1)
      end
    end

    @tag driver: :playwright
    test "reports invalidation when native code closes the tracked context" do
      session = playwright_html("<p>Tracked context</p>")

      assert_raise ArgumentError, ~r/unwrap.*invalidated.*context/i, fn ->
        unwrap(session, fn page -> page |> BrowserPage.context() |> BrowserContext.close!() end)
      end
    end

    @tag driver: :playwright
    test "discovers and cleans up a page created without a pre-armed page expectation" do
      test_pid = self()
      session = playwright_html("<p>Main page</p>")

      session =
        unwrap(session, fn page ->
          send(test_pid, {:untracked_page, page |> BrowserPage.context() |> BrowserContext.new_page!()})
        end)

      assert_receive {:untracked_page, untracked}
      assert length(pages(session)) == 2
      [child] = pages(session) -- [current_page(session)]
      assert Page.url(child) == "about:blank"
      assert current_page(switch_page(session, child)) == child

      browser_context = BrowserPage.context(untracked)
      :ok = GenServer.stop(Fluffy.TestScope.current())

      refute browser_context.guid in browser_context_guids()
    end

    @tag driver: :playwright
    test "passes a native locator for actions Fluffy does not wrap" do
      test_pid = self()
      session = playwright_html(~s(<button ondblclick="this.textContent = 'Twice'">Once</button>))

      session
      |> unwrap(by_role(:button, name: "Once"), fn %BrowserLocator{} = locator ->
        send(test_pid, {:count, BrowserLocator.count!(locator)})
        BrowserLocator.dblclick!(locator)
      end)
      |> expect(:button |> by_role(name: "Twice") |> to_be_visible())

      assert_receive {:count, 1}
    end

    @tag driver: :playwright
    test "adopts a navigation through a native locator" do
      ~s(<a href="/chamber">Chamber</a>)
      |> playwright_html()
      |> unwrap(by_role(:link, name: "Chamber"), &BrowserLocator.click!/1)
      |> expect(Fluffy.Expect.page_to_have_url("/chamber"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    @tag driver: :playwright
    test "resolves a native locator inside its frame" do
      frame = ~s(<button ondblclick="this.textContent = 'Twice'">Once</button><button>Once</button>)
      srcdoc = String.replace(frame, "\"", "&quot;")
      session = playwright_html(~s(<button>Once</button><iframe id="inner" srcdoc="#{srcdoc}"></iframe>))
      inner = frame_locator("#inner")

      session
      |> unwrap(inner |> by_role(:button, name: "Once") |> first(), &BrowserLocator.dblclick!/1)
      |> expect(inner |> by_role(:button, name: "Twice") |> to_be_visible())
      |> expect(:button |> by_role(name: "Once") |> to_have_count(1))
    end

    @tag driver: :playwright
    test "propagates callback exceptions, throws, and exits unchanged" do
      session = playwright_html("<p>Failure</p>")

      assert_raise RuntimeError, "native browser exception", fn ->
        unwrap(session, fn _page -> raise "native browser exception" end)
      end

      assert catch_throw(unwrap(session, fn _page -> throw(:native_browser_throw) end)) ==
               :native_browser_throw

      assert catch_exit(unwrap(session, fn _page -> exit(:native_browser_exit) end)) ==
               :native_browser_exit
    end
  end

  defp start_test_session(backend) do
    start_session(backend,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Endpoint
    )
  end

  defp playwright_html(html) do
    session_for_html(:playwright, html, base_url: Fluffy.TestServer.base_url())
  end
end
