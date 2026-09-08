defmodule Fluffy.Conformance.UnwrapTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Phoenix.ConnTest, only: [get: 2]

  alias Fluffy.Event
  alias Fluffy.Navigation
  alias Fluffy.Page
  alias Fluffy.Playwright.Handle
  alias Fluffy.Session
  alias Fluffy.TestWeb.Endpoint
  alias Phoenix.LiveViewTest.View
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Frame
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

  describe "Static" do
    test "accepts the unchanged current conn and remains pipeable" do
      session = start_test_session(:phoenix)

      session
      |> visit("/chamber")
      |> unwrap(fn %Plug.Conn{} = conn -> conn end)
      |> expect(Page.to_have_status(200))
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
        |> expect(Page.to_have_status(202))
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
        |> expect(Page.to_have_url("/live/session"))
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
      |> expect(Page.to_have_url("/live/chamber-map?step=native"))
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
        |> expect(Page.to_have_url("/live/secret-chamber"))
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
        |> expect(Page.to_have_url("/chamber"))
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
      |> expect(Page.to_have_url("/live/secret-chamber"))
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
    test "passes a documented handle and supports map patterns and explicit connection routing" do
      test_pid = self()
      session = playwright_html("<p id=target>Before</p>")

      session =
        session
        |> unwrap(fn %Handle{} = handle ->
          %{context_id: context_id, page_id: page_id, frame_id: frame_id} = handle

          assert is_binary(context_id)
          assert is_binary(page_id)
          assert is_binary(frame_id)
          assert is_integer(handle.timeout)

          {:ok, _result} =
            Frame.evaluate(frame_id,
              expression: "document.querySelector('#target').textContent = 'After'",
              connection: handle.connection,
              timeout: handle.timeout
            )

          send(test_pid, {:native_handle, handle})
          %{handle | frame_id: "discarded-return-value"}
        end)
        |> expect("After" |> by_text() |> to_be_visible())

      assert_receive {:native_handle, %Handle{} = handle}
      assert Session.page_state(session).frame_id == handle.frame_id
    end

    @tag driver: :playwright
    test "supports BrowserContext and Page operations through the same handle" do
      test_pid = self()
      session = playwright_html("<p>Context operation</p>")

      session
      |> unwrap(fn handle ->
        {:ok, _result} =
          BrowserPage.bring_to_front(handle.page_id,
            connection: handle.connection,
            timeout: handle.timeout
          )

        {:ok, cookies} =
          BrowserContext.cookies(handle.context_id,
            connection: handle.connection,
            timeout: handle.timeout
          )

        send(test_pid, {:cookies, cookies})
        {:error, :ignored_native_result}
      end)
      |> expect("Context operation" |> by_text() |> to_be_visible())

      assert_receive {:cookies, cookies}
      assert is_list(cookies)
    end

    @tag driver: :playwright
    test "exposes the session timeout and leaves native error tuples to the callback" do
      session =
        session_for_html(:playwright, "<p>Still usable</p>",
          base_url: Fluffy.TestServer.base_url(),
          timeout: 1_000
        )

      session
      |> unwrap(fn handle ->
        assert handle.timeout == 1_000

        assert {:error, _reason} =
                 Frame.wait_for_selector(handle.frame_id,
                   selector: "#does-not-exist",
                   timeout: 1,
                   connection: handle.connection
                 )
      end)
      |> expect("Still usable" |> by_text() |> to_be_visible())
    end

    @tag driver: :playwright
    test "synchronizes a native same-frame URL change into the page revision" do
      session = playwright_html("<p>Hash destination</p>")
      before_revision = Session.current_page(session).revision

      session =
        session
        |> unwrap(fn handle ->
          {:ok, _result} =
            Frame.evaluate(handle.frame_id,
              expression: "location.hash = 'native'",
              connection: handle.connection,
              timeout: handle.timeout
            )
        end)
        |> expect(Page.to_have_url("/harness#native"))

      assert Session.current_page(session).revision == before_revision + 1
    end

    @tag driver: :playwright
    test "synchronizes a native full document navigation" do
      session = playwright_html("<p>Before navigation</p>")

      session
      |> unwrap(fn handle ->
        {:ok, _response} =
          Frame.goto(handle.frame_id,
            url: "/chamber",
            wait_until: "load",
            connection: handle.connection,
            timeout: handle.timeout
          )
      end)
      |> expect(Page.to_have_url("/chamber"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    @tag driver: :playwright
    test "composes with a pre-armed navigation expectation" do
      session = playwright_html("<p>Before captured navigation</p>")

      session =
        wait_for(session, Event.navigation(:native_navigation), fn session ->
          unwrap(session, fn handle ->
            {:ok, _response} =
              Frame.goto(handle.frame_id,
                url: "/chamber",
                wait_until: "load",
                connection: handle.connection,
                timeout: handle.timeout
              )
          end)
        end)

      session
      |> expect(
        Navigation.to_have_from_url(
          :native_navigation,
          Fluffy.TestServer.base_url() <> "/harness"
        )
      )
      |> expect(Navigation.to_have_url(:native_navigation, Fluffy.TestServer.base_url() <> "/chamber"))
      |> expect(Navigation.to_have_status(:native_navigation, 200))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    @tag driver: :playwright
    test "composes with a pre-armed page expectation" do
      session = playwright_html("<p>Main page</p>")

      session =
        wait_for(session, Event.popup(:native_child), fn session ->
          unwrap(session, fn handle ->
            {:ok, page} =
              BrowserContext.new_page(handle.context_id,
                connection: handle.connection,
                timeout: handle.timeout
              )

            {:ok, _response} =
              Frame.goto(page.main_frame.guid,
                url: "/chamber",
                wait_until: "load",
                connection: handle.connection,
                timeout: handle.timeout
              )
          end)
        end)

      session
      |> switch_page(:native_child)
      |> expect(Page.to_have_url(Fluffy.TestServer.base_url() <> "/chamber"))
      |> expect(Page.to_have_opener(:main))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    @tag driver: :playwright
    test "captures a blank page without requiring an HTTP response" do
      session = playwright_html("<p>Main page</p>")

      session =
        wait_for(session, Event.popup(:blank_child), fn session ->
          unwrap(session, fn handle ->
            assert {:ok, _page} =
                     BrowserContext.new_page(handle.context_id,
                       connection: handle.connection,
                       timeout: handle.timeout
                     )
          end)
        end)

      assert Page.url(page(session, :blank_child)) == "about:blank"

      session
      |> switch_page(:blank_child)
      |> expect(Page.to_have_url("about:blank"))
    end

    @tag driver: :playwright
    test "reports invalidation when native code closes the tracked page" do
      session = playwright_html("<p>Tracked page</p>")

      assert_raise ArgumentError, ~r/unwrap.*invalidated.*page/i, fn ->
        unwrap(session, fn handle ->
          {:ok, _result} =
            BrowserPage.close(handle.page_id,
              connection: handle.connection,
              timeout: handle.timeout
            )
        end)
      end
    end

    @tag driver: :playwright
    test "reports invalidation when native code closes the tracked context" do
      session = playwright_html("<p>Tracked context</p>")

      assert_raise ArgumentError, ~r/unwrap.*invalidated.*context/i, fn ->
        unwrap(session, fn handle ->
          {:ok, _result} =
            BrowserContext.close(handle.context_id,
              connection: handle.connection,
              timeout: handle.timeout
            )
        end)
      end
    end

    @tag driver: :playwright
    test "does not adopt a page created without a pre-armed page expectation" do
      test_pid = self()
      session = playwright_html("<p>Main page</p>")

      session =
        unwrap(session, fn handle ->
          {:ok, page} =
            BrowserContext.new_page(handle.context_id,
              connection: handle.connection,
              timeout: handle.timeout
            )

          send(test_pid, {:untracked_page, page.guid, handle.connection, handle.timeout})
        end)

      assert page_names(session) == [:main]
      assert_receive {:untracked_page, page_id, connection, timeout}

      :ok = GenServer.stop(Fluffy.TestScope.current())

      assert {:error, _reason} =
               BrowserPage.bring_to_front(page_id,
                 connection: connection,
                 timeout: timeout
               )
    end

    @tag driver: :playwright
    test "propagates callback exceptions, throws, and exits unchanged" do
      session = playwright_html("<p>Failure</p>")

      assert_raise RuntimeError, "native browser exception", fn ->
        unwrap(session, fn _handle -> raise "native browser exception" end)
      end

      assert catch_throw(unwrap(session, fn _handle -> throw(:native_browser_throw) end)) ==
               :native_browser_throw

      assert catch_exit(unwrap(session, fn _handle -> exit(:native_browser_exit) end)) ==
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
