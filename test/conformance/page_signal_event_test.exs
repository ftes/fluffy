defmodule Fluffy.Conformance.PageSignalEventTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright, except: [wait_for: 3]

  alias Fluffy.Event
  alias Fluffy.Frame
  alias Fluffy.Playwright
  alias Fluffy.Session
  alias Fluffy.TestHTTPFixtures

  describe "console" do
    @tag driver: :playwright
    test "a wait resolves with the message's metadata, and predicates skip others" do
      {session, fixture} = session()
      pending = wait_for(session, Event.console(&(&1.text == "from button")))
      other = wait_for(session, Event.console(&(&1.type == "warning")))

      Playwright.evaluate(session, "console.log('skipped')")
      click(session, by_role(:button, name: "Log"))

      assert %Fluffy.ConsoleMessage{type: "error", text: "from button"} = message = await(pending)
      assert message.page == current_page(session)
      assert is_number(message.timestamp)
      assert message.location.url == TestHTTPFixtures.url(fixture, "/start")

      Playwright.evaluate(session, "console.warn('warned')")
      assert await(other).text == "warned"
    end

    @tag driver: :playwright
    test "unwrap reaches the native message until the session closes" do
      {session, _fixture} = session()
      pending = wait_for(session, Event.console())
      Playwright.evaluate(session, "console.log('native', 7)")
      message = await(pending)

      assert message |> unwrap_and_return(&PlaywrightEx.ConsoleMessage.args/1) |> length() == 2

      close_session(session)
      assert_raise ArgumentError, ~r/session is closed/, fn -> unwrap_and_return(message, & &1) end
    end

    @tag driver: :playwright
    test "listeners stop after off and expect_event inspects the message" do
      {session, _fixture} = session()
      owner = self()
      handler = fn message -> send(owner, {:console, message.text}) end

      on(session, Event.console(), handler)
      Playwright.evaluate(session, "console.log('heard')")
      assert_receive {:console, "heard"}, Session.timeout(session)

      off(session, Event.console(), handler)
      Playwright.evaluate(session, "console.log('unheard')")
      refute_receive {:console, "unheard"}, 200

      assert expect_event(
               session,
               Event.console(&(&1.text == "expected")),
               &Playwright.evaluate(&1, "console.log('expected')"),
               fn message -> send(owner, {:expected, message.type}) end
             ) == session

      assert_received {:expected, "log"}
    end

    @tag driver: :playwright
    test "stays bound to the page selected at registration" do
      {session, _fixture} = session()
      pending = wait_for(session, Event.console())
      other = switch_page(session, new_page(session))
      Playwright.evaluate(other, "console.log('other page')")
      Playwright.evaluate(session, "console.log('main page')")
      assert await(pending).text == "main page"
    end
  end

  describe "page_error" do
    @tag driver: :playwright
    test "an uncaught Error resolves with its name, message, stack and page" do
      {session, _fixture} = session()
      pending = wait_for(session, Event.page_error())
      Playwright.evaluate(session, "setTimeout(() => { throw new RangeError('boom') }, 0); 1")

      assert %Fluffy.PageError{name: "RangeError"} = error = await(pending)
      assert error.message =~ "boom"
      assert is_binary(error.stack)
      assert error.page == current_page(session)
      assert unwrap_and_return(error, &Exception.message/1) =~ "boom"
    end

    @tag driver: :playwright
    test "a thrown value that is not an Error resolves with its text as message" do
      {session, _fixture} = session()
      pending = wait_for(session, Event.page_error())
      Playwright.evaluate(session, "setTimeout(() => { throw 'thrown string' }, 0); 1")

      assert %Fluffy.PageError{} = error = await(pending)
      assert error.message =~ "thrown string"
      assert error.page == current_page(session)
      assert unwrap_and_return(error, &Exception.message/1) =~ "thrown string"
    end

    @tag driver: :playwright
    test "on delivers each error and off removes it" do
      {session, _fixture} = session()
      owner = self()
      handler = fn error -> send(owner, {:page_error, error.message}) end

      on(session, Event.page_error(&(&1.message =~ "first")), handler)
      Playwright.evaluate(session, "setTimeout(() => { throw new Error('first') }, 0); 1")
      assert_receive {:page_error, message}, Session.timeout(session)
      assert message =~ "first"

      off(session, Event.page_error(), handler)
      Playwright.evaluate(session, "setTimeout(() => { throw new Error('first again') }, 0); 1")
      refute_receive {:page_error, _message}, 200
    end
  end

  describe "request_failed and request_finished" do
    @tag driver: :playwright
    test "a failed request resolves on page and context scope and exposes its failure" do
      {session, _fixture} = session()
      url = closed_port_url()
      match = &String.starts_with?(&1.url, url)
      pending = wait_for(session, Event.request_failed(match))
      context = wait_for(session, Event.request_failed(match), scope: :context)
      finished = wait_for(session, Event.request_finished(match), timeout: 200)

      Playwright.evaluate(session, "url => { fetch(url).catch(() => {}); return true }", url)

      assert %Fluffy.Request{method: "GET", resource_type: "fetch"} = request = await(pending)
      assert request.page == current_page(session)
      assert await(context) == request
      assert %{errorText: reason} = unwrap_and_return(request, &PlaywrightEx.Request.failure/1)
      assert is_binary(reason)
      assert_raise ExUnit.AssertionError, ~r/no matching request_finished event/, fn -> await(finished) end
    end

    @tag driver: :playwright
    test "an error status finishes a request, on page and context scope" do
      {session, _fixture} = session()
      match = &String.ends_with?(&1.url, "/missing")
      pending = wait_for(session, Event.request_finished(match))
      context = wait_for(session, Event.request_finished(match), scope: :context)
      failed = wait_for(session, Event.request_failed(match), timeout: 200)

      Playwright.evaluate(session, "fetch('missing'); true")

      assert %Fluffy.Request{method: "GET"} = request = await(pending)
      assert await(context) == request
      assert {:ok, %PlaywrightEx.Response{}} = unwrap_and_return(request, &PlaywrightEx.Request.response/1)
      assert_raise ExUnit.AssertionError, ~r/no matching request_failed event/, fn -> await(failed) end
    end

    @tag driver: :playwright
    test "on observes a finished request and off removes the listener" do
      {session, _fixture} = session()
      owner = self()
      handler = fn request -> send(owner, {:finished, URI.parse(request.url).path}) end

      on(session, Event.request_finished(&String.ends_with?(&1.url, "/api")), handler)
      Playwright.evaluate(session, "fetch('api'); true")
      assert_receive {:finished, path}, Session.timeout(session)
      assert String.ends_with?(path, "/api")

      off(session, Event.request_finished(), handler)
      Playwright.evaluate(session, "fetch('api'); true")
      refute_receive {:finished, _path}, 200
    end
  end

  describe "load, dom_content_loaded and crash" do
    @tag driver: :playwright
    test "a navigation resolves load and dom_content_loaded with the page" do
      {session, fixture} = session()
      loaded = wait_for(session, Event.load())
      content_loaded = wait_for(session, Event.dom_content_loaded())

      visit(session, TestHTTPFixtures.path(fixture, "/child"))

      assert await(content_loaded) == current_page(session)
      assert await(loaded) == current_page(session)
    end

    @tag driver: :playwright
    test "predicates and expect_event apply to load" do
      {session, fixture} = session()
      page = current_page(session)

      assert expect_event(
               session,
               Event.load(&(&1 == page)),
               &visit(&1, TestHTTPFixtures.path(fixture, "/child")),
               fn loaded -> assert loaded == page end
             ) == session

      pending = wait_for(session, Event.load(fn _page -> false end), timeout: 200)
      visit(session, TestHTTPFixtures.path(fixture, "/start"))
      assert_raise ExUnit.AssertionError, ~r/no matching load event/, fn -> await(pending) end
    end

    @tag driver: :playwright
    @tag skip: if(not playwright_engine?(:chromium), do: "only Chromium crashes a page by URL")
    test "a crash resolves the crash event and still fails other waits" do
      {session, _fixture} = session()
      page = current_page(session)
      crashed = wait_for(session, Event.crash())
      other = wait_for(session, Event.console())
      browser_page = Session.page_state(session).page

      {:ok, _pid} = Task.start(fn -> PlaywrightEx.Page.goto(browser_page, "chrome://crash") end)

      assert await(crashed) == page
      assert_raise ExUnit.AssertionError, ~r/event source crashed/, fn -> await(other) end
    end
  end

  describe "frame_attached and frame_detached" do
    @tag driver: :playwright
    test "resolve with the child frame and honor predicates" do
      {session, _fixture} = session()
      attached = wait_for(session, Event.frame_attached(&Frame.parent_frame/1))
      detached = wait_for(session, Event.frame_detached())

      Playwright.evaluate(session, "document.body.appendChild(document.createElement('iframe')); true")

      frame = await(attached)
      assert Frame.page(frame) == current_page(session)
      assert %Frame{} = Frame.parent_frame(frame)

      Playwright.evaluate(session, "document.querySelector('iframe').remove(); true")

      assert %Frame{} = gone = await(detached)
      assert unwrap_and_return(gone, &PlaywrightEx.Frame.is_detached/1)
      assert Frame.page(gone) == current_page(session)
    end

    @tag driver: :playwright
    test "on and off observe attachments" do
      {session, _fixture} = session()
      owner = self()
      handler = fn frame -> send(owner, {:attached, frame}) end

      on(session, Event.frame_attached(), handler)
      Playwright.evaluate(session, "document.body.appendChild(document.createElement('iframe')); true")
      assert_receive {:attached, %Frame{}}, Session.timeout(session)

      off(session, Event.frame_attached(), handler)
      Playwright.evaluate(session, "document.body.appendChild(document.createElement('iframe')); true")
      refute_receive {:attached, _frame}, 200
    end
  end

  describe "worker and web_socket" do
    @tag driver: :playwright
    test "a worker resolves with its url and page, and unwraps" do
      {session, _fixture} = session()
      pending = wait_for(session, Event.worker(&String.starts_with?(&1.url, "blob:")))

      Playwright.evaluate(
        session,
        "window.w = new Worker(URL.createObjectURL(new Blob(['1'], {type: 'application/javascript'}))); true"
      )

      assert %Fluffy.Worker{} = worker = await(pending)
      assert worker.page == current_page(session)
      assert unwrap_and_return(worker, &PlaywrightEx.Worker.evaluate!(&1, "1 + 1")) == 2

      close_session(session)
      assert_raise ArgumentError, ~r/session is closed/, fn -> unwrap_and_return(worker, & &1) end
    end

    @tag driver: :playwright
    test "on observes a worker and off removes the listener" do
      {session, _fixture} = session()
      owner = self()
      handler = fn worker -> send(owner, {:worker, worker.url}) end
      spawn_worker = "window.w = new Worker(URL.createObjectURL(new Blob(['1'], {type: 'text/javascript'}))); true"

      on(session, Event.worker(), handler)
      Playwright.evaluate(session, spawn_worker)
      assert_receive {:worker, "blob:" <> _url}, Session.timeout(session)

      off(session, Event.worker(), handler)
      Playwright.evaluate(session, spawn_worker)
      refute_receive {:worker, _url}, 200
    end

    @tag driver: :playwright
    test "a web socket resolves with its url and page, and unwraps" do
      {session, _fixture} = session()
      url = String.replace_prefix(Fluffy.TestServer.base_url(), "http", "ws") <> "/live/websocket?vsn=2.0.0"
      pending = wait_for(session, Event.web_socket(&(&1.url == url)))

      Playwright.evaluate(session, "url => { window.s = new WebSocket(url); return true }", url)

      assert %Fluffy.WebSocket{url: ^url} = socket = await(pending)
      assert socket.page == current_page(session)
      assert unwrap_and_return(socket, &PlaywrightEx.WebSocket.url/1) == url

      close_session(session)
      assert_raise ArgumentError, ~r/session is closed/, fn -> unwrap_and_return(socket, & &1) end
    end
  end

  @phoenix_capabilities [
    console: :browser_events,
    page_error: :browser_events,
    worker: :browser_events,
    web_socket: :browser_events,
    request_failed: :browser_network_events,
    request_finished: :browser_network_events,
    frame_attached: :browser_frame_events,
    frame_detached: :browser_frame_events,
    load: :pages,
    dom_content_loaded: :pages,
    crash: :pages
  ]

  for driver <- [:static, :live] do
    test "#{driver} rejects browser events before invoking an action" do
      session =
        case unquote(driver) do
          :static -> session_for_html(:static, "<h1>Main</h1>")
          :live -> :phoenix |> start_session() |> visit("/live/chamber-map")
        end

      for {type, capability} <- @phoenix_capabilities do
        event = apply(Event, type, [])

        error =
          assert_raise Fluffy.CapabilityError, fn ->
            expect_event(session, event, fn _ -> flunk("unsupported action ran") end)
          end

        assert error.capability == capability
        assert error.driver == unquote(driver)
      end
    end
  end

  test "only network events accept a scope" do
    session = session_for_html(:static, "<h1>Main</h1>")

    for type <- [:console, :page_error, :load, :dom_content_loaded, :crash, :frame_attached, :worker, :web_socket] do
      assert_raise NimbleOptions.ValidationError, fn -> wait_for(session, apply(Event, type, []), scope: :context) end
    end
  end

  defp session do
    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{body: ~s|<!doctype html><button onclick="console.error('from button')">Log</button>|}

          "/child" ->
            %{body: "<!doctype html><h1>Child</h1>"}

          "/api" ->
            %{body: "ok"}

          "/missing" ->
            %{status: 404, body: "gone"}
        end
      end)

    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url())
      |> visit(TestHTTPFixtures.path(fixture, "/start"))

    {session, fixture}
  end

  defp closed_port_url do
    {:ok, listener} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(listener)
    :ok = :gen_tcp.close(listener)
    "http://127.0.0.1:#{port}/"
  end
end
