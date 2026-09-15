defmodule Fluffy.PlaywrightEventCaptureTest do
  use Fluffy.TestCase, async: true

  import Fluffy

  alias Fluffy.Backend.Playwright, as: Backend
  alias Fluffy.Playwright.Response

  @tag driver: :playwright
  test "ordinary capture retains the first response when several arrive before await" do
    fixture = Fluffy.TestHTTPFixtures.register(%{body: "ok"})
    session = session_for_html(:playwright, "<h1>Events</h1>")

    unwrap(session, fn handle ->
      {:ok, _session, resource} = Backend.arm_event(session, :response, matcher: ~r/./, timeout: handle.timeout)

      try do
        for suffix <- ["first", "second"] do
          url = Fluffy.TestHTTPFixtures.url(fixture, suffix)

          {:ok, _} =
            PlaywrightEx.Frame.goto(handle.frame_id, connection: handle.connection, url: url, timeout: handle.timeout)
        end

        assert {:ok, _session, response} = Backend.await_event(session, resource, handle.timeout)
        assert String.ends_with?(response.url, "/first")
      after
        Backend.disarm_event(resource)
      end
    end)
  end

  @tag driver: :playwright
  test "capture expires while the action is still running" do
    session = session_for_html(:playwright, "<h1>Events</h1>")

    unwrap(session, fn handle ->
      {:ok, _session, resource} = Backend.arm_event(session, :navigation, timeout: 20)

      try do
        # Waiting on the worker makes this independent of scheduler timing.
        worker = resource.waiter.task.pid
        reference = Process.monitor(worker)
        assert_receive {:DOWN, ^reference, :process, ^worker, _reason}, 1_000

        {:ok, _} =
          PlaywrightEx.Frame.evaluate(handle.frame_id,
            connection: handle.connection,
            expression: "location.hash = 'too-late'",
            timeout: handle.timeout
          )

        assert {:error, %{reason: :timeout}} = Backend.await_event(session, resource, handle.timeout)
      after
        Backend.disarm_event(resource)
      end
    end)
  end

  @tag driver: :playwright
  test "captured navigation retains its response after a later document commits" do
    fixture =
      Fluffy.TestHTTPFixtures.register(fn request ->
        %{status: if(request.path == "/first", do: 201, else: 202), body: "<h1>Document</h1>"}
      end)

    session = session_for_html(:playwright, "<h1>Events</h1>")

    unwrap(session, fn handle ->
      {:ok, _session, resource} = Backend.arm_event(session, :navigation, timeout: handle.timeout)

      try do
        for suffix <- ["first", "second"] do
          {:ok, _} =
            PlaywrightEx.Frame.goto(handle.frame_id,
              connection: handle.connection,
              url: Fluffy.TestHTTPFixtures.url(fixture, suffix),
              timeout: handle.timeout
            )
        end

        assert {:ok, _session, %{status: 201}} = Backend.await_event(session, resource, handle.timeout)

        assert {:ok, %{status: 202}} =
                 Response.for_document(handle.frame_id, connection: handle.connection, timeout: handle.timeout)
      after
        Backend.disarm_event(resource)
      end
    end)
  end

  @tag driver: :playwright
  test "redirected popup capture works without request or response subscriptions" do
    fixture =
      Fluffy.TestHTTPFixtures.register(fn request ->
        case request.path do
          "/redirect" -> %{status: 302, headers: [{"location", "final"}], body: ""}
          "/final" -> %{status: 203, body: "<script>history.replaceState({}, '', 'patched')</script><h1>Popup</h1>"}
        end
      end)

    url = Fluffy.TestHTTPFixtures.url(fixture, "/redirect")
    session = session_for_html(:playwright, ~s(<a href="#{url}" target="_blank">Open</a>))

    unwrap(session, fn handle ->
      for event <- [:request, :response] do
        {:ok, _} =
          PlaywrightEx.BrowserContext.update_subscription(handle.context_id,
            connection: handle.connection,
            event: event,
            enabled: false,
            timeout: handle.timeout
          )
      end

      session = wait_for(session, Fluffy.Event.popup(:details), &click(&1, Fluffy.Locator.by_role(:link, name: "Open")))
      popup = page(session, :details)
      assert Fluffy.Page.status(popup) == 203
      assert Fluffy.Page.url(popup) == Fluffy.TestHTTPFixtures.url(fixture, "/patched")
    end)
  end

  for reason <- [:normal, :shutdown] do
    @tag driver: :playwright
    test "one-shot capture releases its subscription when its owner exits #{reason}" do
      test_pid = self()
      session = session_for_html(:playwright, "<h1>Owner cleanup</h1>")

      unwrap(session, fn handle ->
        key = {handle.context_id, "response"}

        owner =
          spawn(fn ->
            {:ok, _session, resource} = Backend.arm_event(session, :response, matcher: ~r/./, timeout: handle.timeout)
            send(test_pid, {:capture, resource})

            receive do
              :finish -> exit(unquote(reason))
            end
          end)

        assert_receive {:capture, resource}
        assert subscription_active?(handle.connection, key)
        waiter = resource.waiter.task.pid
        reference = Process.monitor(waiter)
        send(owner, :finish)
        assert_receive {:DOWN, ^reference, :process, ^waiter, _reason}
        assert_eventually(fn -> not subscription_active?(handle.connection, key) end)
      end)
    end
  end

  @tag driver: :playwright
  test "disarming one capture keeps another subscription active" do
    fixture = Fluffy.TestHTTPFixtures.register(%{body: "ok"})
    session = session_for_html(:playwright, "<h1>Events</h1>")
    {:ok, _session, first} = Backend.arm_event(session, :response, matcher: ~r/./, timeout: 1_000)
    {:ok, _session, second} = Backend.arm_event(session, :response, matcher: ~r/./, timeout: 1_000)

    try do
      Backend.disarm_event(first)
      Backend.disarm_event(first)

      unwrap(session, fn handle ->
        {:ok, _} =
          PlaywrightEx.Frame.goto(handle.frame_id,
            connection: handle.connection,
            url: Fluffy.TestHTTPFixtures.url(fixture),
            timeout: handle.timeout
          )
      end)

      assert {:ok, _session, %Fluffy.HTTPEvent{status: 200}} = Backend.await_event(session, second, 1_000)
    after
      Backend.disarm_event(first)
      Backend.disarm_event(second)
    end
  end

  for type <- [:navigation, :response] do
    @tag driver: :playwright
    test "captured #{type} metadata survives page closure before await" do
      fixture = Fluffy.TestHTTPFixtures.register(%{status: 201, body: "ok"})
      session = session_for_html(:playwright, "<h1>Events</h1>")
      {:ok, _session, resource} = Backend.arm_event(session, unquote(type), matcher: ~r/./, timeout: 1_000)

      try do
        unwrap(session, fn handle ->
          {:ok, _} =
            PlaywrightEx.Frame.goto(handle.frame_id,
              connection: handle.connection,
              url: Fluffy.TestHTTPFixtures.url(fixture),
              timeout: handle.timeout
            )

          waiter = resource.waiter.task.pid
          monitor = Process.monitor(waiter)
          assert_receive {:DOWN, ^monitor, :process, ^waiter, _}, 1_000
        end)

        {:ok, _} =
          PlaywrightEx.Page.close(Fluffy.Session.page_state(session).page_id,
            connection: session.context.connection,
            timeout: session.context.timeout
          )

        assert {:ok, _session, %{status: 201}} = Backend.await_event(session, resource, 1_000)
      after
        Backend.disarm_event(resource)
      end
    end
  end

  @tag driver: :playwright
  test "disarming a captured response discards its Task result" do
    fixture = Fluffy.TestHTTPFixtures.register(%{body: "ok"})
    session = session_for_html(:playwright, "<h1>Events</h1>")
    {:ok, _session, resource} = Backend.arm_event(session, :response, matcher: ~r/./, timeout: 1_000)

    unwrap(session, fn handle ->
      {:ok, _} =
        PlaywrightEx.Frame.goto(handle.frame_id,
          connection: handle.connection,
          url: Fluffy.TestHTTPFixtures.url(fixture),
          timeout: handle.timeout
        )
    end)

    waiter = resource.waiter.task.pid
    monitor = Process.monitor(waiter)
    assert_receive {:DOWN, ^monitor, :process, ^waiter, _}, 1_000
    Backend.disarm_event(resource)
    reference = resource.waiter.task.ref
    refute_receive {^reference, _snapshot}
  end

  defp subscription_active?(connection, key) do
    {:started, state} = :sys.get_state(connection)
    Map.has_key?(state.subscriptions, key)
  end

  defp assert_eventually(fun, attempts \\ 100)
  defp assert_eventually(fun, 0), do: assert(fun.())

  defp assert_eventually(fun, attempts) do
    if !fun.() do
      Process.sleep(10)
      assert_eventually(fun, attempts - 1)
    end
  end
end
