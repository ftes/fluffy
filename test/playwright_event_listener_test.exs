defmodule Fluffy.PlaywrightEventListenerTest do
  use Fluffy.TestCase, async: true

  import Fluffy

  alias Fluffy.Playwright.NavigationObserver
  alias Fluffy.Playwright.SubscriptionRegistry

  @tag driver: :playwright
  test "a navigation observer stops and releases its subscription when its owner exits" do
    test_pid = self()
    session = session_for_html(:playwright, "<p>Observer owner</p>")

    unwrap(session, fn handle ->
      key = {handle.connection, handle.context_id, :response}
      baseline = Map.fetch!(:sys.get_state(SubscriptionRegistry), key)

      owner =
        spawn(fn ->
          %NavigationObserver{listener: listener} =
            NavigationObserver.arm(
              handle.context_id,
              handle.page_id,
              handle.frame_id,
              handle.timeout,
              handle.connection
            )

          send(test_pid, {:owned_listener, listener})

          receive do
            :finish -> :ok
          end
        end)

      assert_receive {:owned_listener, listener}
      assert Process.alive?(listener)
      assert Map.fetch!(:sys.get_state(SubscriptionRegistry), key) == baseline + 1

      reference = Process.monitor(listener)
      send(owner, :finish)

      assert_receive {:DOWN, ^reference, :process, ^listener, :normal}
      assert Map.fetch!(:sys.get_state(SubscriptionRegistry), key) == baseline
    end)
  end

  @tag driver: :playwright
  test "ordinary capture retains the first response when several arrive before await" do
    fixture = Fluffy.TestHTTPFixtures.register(%{body: "ok"})
    session = session_for_html(:playwright, "<h1>Events</h1>")

    unwrap(session, fn handle ->
      {:ok, listener} =
        Fluffy.PlaywrightEventListener.start_link(
          connection: handle.connection,
          guid: handle.context_id,
          event: :response,
          subscription: :response,
          timeout: handle.timeout
        )

      try do
        for suffix <- ["first", "second"] do
          url = Fluffy.TestHTTPFixtures.url(fixture, suffix)

          {:ok, _} =
            PlaywrightEx.Frame.goto(handle.frame_id, connection: handle.connection, url: url, timeout: handle.timeout)
        end

        assert {:ok, %{params: %{response: %{guid: response_id}}}} = Fluffy.PlaywrightEventListener.await(listener)
        response = PlaywrightEx.Connection.initializer!(handle.connection, response_id)
        assert String.ends_with?(response.url, "/first")
      after
        Fluffy.PlaywrightEventListener.stop(listener)
      end
    end)
  end

  @tag driver: :playwright
  test "capture expires while the action is still running" do
    session = session_for_html(:playwright, "<h1>Events</h1>")

    unwrap(session, fn handle ->
      {:ok, listener} =
        Fluffy.PlaywrightEventListener.start_link(
          connection: handle.connection,
          guid: handle.frame_id,
          event: :navigated,
          timeout: 20
        )

      try do
        # Waiting on the worker makes this independent of scheduler timing.
        worker = :sys.get_state(listener).task.pid
        reference = Process.monitor(worker)
        assert_receive {:DOWN, ^reference, :process, ^worker, _reason}, 1_000

        {:ok, _} =
          PlaywrightEx.Frame.evaluate(handle.frame_id,
            connection: handle.connection,
            expression: "location.hash = 'too-late'",
            timeout: handle.timeout
          )

        assert {:error, %{reason: :timeout}} = Fluffy.PlaywrightEventListener.await(listener)
      after
        Fluffy.PlaywrightEventListener.stop(listener)
      end
    end)
  end

  @tag driver: :playwright
  test "navigation observers survive idle time and associate responses with committed requests" do
    fixture =
      Fluffy.TestHTTPFixtures.register(fn request ->
        %{status: if(request.path == "/first", do: 201, else: 202), body: "<h1>Document</h1>"}
      end)

    session = session_for_html(:playwright, "<h1>Events</h1>")

    unwrap(session, fn handle ->
      observer = NavigationObserver.arm(handle.context_id, handle.page_id, handle.frame_id, 100, handle.connection)

      try do
        Process.sleep(120)

        {:ok, first} =
          PlaywrightEx.EventWaiter.arm(handle.frame_id, :navigated,
            connection: handle.connection,
            timeout: handle.timeout
          )

        for suffix <- ["first", "second"] do
          {:ok, _} =
            PlaywrightEx.Frame.goto(handle.frame_id,
              connection: handle.connection,
              url: Fluffy.TestHTTPFixtures.url(fixture, suffix),
              timeout: handle.timeout
            )
        end

        {:ok, event} = PlaywrightEx.EventWaiter.await(first)
        request_id = event.params.new_document.request.guid
        assert {:ok, %{status: 201}} = NavigationObserver.await(observer, handle.timeout, request_id: request_id)
        assert {:ok, %{status: 202}} = NavigationObserver.await(observer, handle.timeout)
      after
        NavigationObserver.stop(observer)
      end
    end)
  end

  for reason <- [:normal, :shutdown] do
    @tag driver: :playwright
    test "one-shot capture releases its subscription when its owner exits #{reason}" do
      test_pid = self()
      session = session_for_html(:playwright, "<h1>Owner cleanup</h1>")

      unwrap(session, fn handle ->
        key = {handle.connection, handle.context_id, :response}
        baseline = Map.get(:sys.get_state(SubscriptionRegistry), key, 0)

        owner =
          spawn(fn ->
            {:ok, listener} =
              Fluffy.PlaywrightEventListener.start_link(
                connection: handle.connection,
                guid: handle.context_id,
                event: :response,
                subscription: :response,
                timeout: handle.timeout
              )

            send(test_pid, {:capture_listener, listener})

            receive do
              :finish -> exit(unquote(reason))
            end
          end)

        assert_receive {:capture_listener, listener}
        assert Map.fetch!(:sys.get_state(SubscriptionRegistry), key) == baseline + 1
        reference = Process.monitor(listener)
        send(owner, :finish)
        assert_receive {:DOWN, ^reference, :process, ^listener, _reason}
        assert Map.get(:sys.get_state(SubscriptionRegistry), key, 0) == baseline
      end)
    end
  end
end
