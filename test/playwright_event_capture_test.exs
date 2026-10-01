defmodule Fluffy.PlaywrightEventCaptureTest do
  use Fluffy.TestCase, async: true

  import Fluffy

  alias Fluffy.Event
  alias Fluffy.Event.Subscription
  alias Fluffy.Playwright
  alias Fluffy.Session
  alias Fluffy.TestHTTPFixtures

  @moduletag driver: :playwright

  test "retains the first response when several arrive before await" do
    fixture = TestHTTPFixtures.register(%{body: "ok"})
    session = session_for_html(:playwright, "<h1>Events</h1>")
    pending = wait_for(session, Event.response())
    visit(session, TestHTTPFixtures.url(fixture, "/first"))
    visit(session, TestHTTPFixtures.url(fixture, "/second"))
    assert String.ends_with?(await(pending).url, "/first")
  end

  test "a wait expires independently of await or later actions" do
    session = session_for_html(:playwright, "<h1>Events</h1>")
    pending = wait_for(session, Event.frame_navigated(), timeout: 0)
    Playwright.evaluate(session, "location.hash = 'too-late'; true")
    assert_raise ExUnit.AssertionError, ~r/timeout/, fn -> await(pending) end
  end

  for reason <- [:normal, :shutdown] do
    test "an unawaited wait releases its subscription when its owner exits #{reason}" do
      parent = self()
      session = session_for_html(:playwright, "<h1>Owner cleanup</h1>")
      context = Session.context(session)
      key = {context.context_id, "response"}

      owner =
        spawn(fn ->
          pending = wait_for(session, Event.response())
          send(parent, {:pending, pending})

          receive do
            :finish -> exit(unquote(reason))
          end
        end)

      assert_receive {:pending, pending}
      assert subscription_active?(context.connection, key)
      monitor = Process.monitor(pending.pid)
      send(owner, :finish)
      assert_receive {:DOWN, ^monitor, :process, _, _}
      refute subscription_active?(context.connection, key)
    end
  end

  test "cancelling one wait retains another and is idempotent" do
    fixture = TestHTTPFixtures.register(%{body: "ok"})
    session = session_for_html(:playwright, "<h1>Events</h1>")
    first = wait_for(session, Event.response())
    second = wait_for(session, Event.response())
    Subscription.cancel(first.pid)
    Subscription.cancel(first.pid)
    visit(session, TestHTTPFixtures.url(fixture))
    assert await(second).status == 200
  end

  test "settled response metadata survives source closure before await" do
    fixture = TestHTTPFixtures.register(%{status: 201, body: "ok"})
    session = session_for_html(:playwright, "<h1>Events</h1>")
    pending = wait_for(session, Event.response())
    visit(session, TestHTTPFixtures.url(fixture))
    assert_eventually(fn -> :sys.get_state(pending.pid).outcome != nil end)
    close_page(session)
    assert await(pending).status == 201
  end

  test "source closure and crash resolve outstanding waits" do
    session = session_for_html(:playwright, "<h1>Events</h1>")
    pending = wait_for(session, Event.response())
    close_page(session)
    assert_raise ExUnit.AssertionError, ~r/closed/, fn -> await(pending) end

    session = session_for_html(:playwright, "<h1>Crash signal</h1>")
    pending = wait_for(session, Event.download())
    # Feed the actual protocol lifecycle signal without crashing the shared browser.
    send(pending.pid, {:playwright_msg, %{guid: Session.page_state(session).page_id, method: :crash}})
    assert_raise ExUnit.AssertionError, ~r/crashed/, fn -> await(pending) end
  end

  test "a settled wait releases managed subscriptions before its value is consumed" do
    fixture = TestHTTPFixtures.register(%{body: "ok"})
    session = session_for_html(:playwright, "<h1>Events</h1>")
    context = Session.context(session)
    pending = wait_for(session, Event.response())
    visit(session, TestHTTPFixtures.url(fixture))
    assert_eventually(fn -> :sys.get_state(pending.pid).outcome != nil end)
    refute subscription_active?(context.connection, {context.context_id, "response"})
    Subscription.cancel(pending.pid)
    refute Process.alive?(pending.pid)
  end

  test "page discovery and event decoding retain one page subscription" do
    fixture = TestHTTPFixtures.register(%{body: "ok"})
    session = session_for_html(:playwright, "<h1>Main</h1>")
    page_wait = wait_for(session, Event.page())
    session = new_page(session, :other)
    assert await(page_wait) == current_page(session)

    first = wait_for(session, Event.response())
    second = wait_for(session, Event.response())
    visit(session, TestHTTPFixtures.url(fixture))
    assert await(first).page == current_page(session)
    assert await(second).page == current_page(session)

    context = Session.context(session)
    page_id = Session.page_state(session).page_id
    {:started, state} = :sys.get_state(context.connection)
    assert MapSet.size(state.subscriptions[{page_id, "console"}]) == 1
    assert length(pages(session)) == 2
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
