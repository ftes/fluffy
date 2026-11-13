defmodule Fluffy.PlaywrightEventCaptureTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Playwright

  alias Fluffy.Event
  alias Fluffy.Event.Subscription
  alias Fluffy.Playwright
  alias Fluffy.Session
  alias Fluffy.Support.HTTPFixtures
  alias PlaywrightEx.Client.EventEmitter

  @moduletag driver: :playwright

  test "retains the first response when several arrive before await" do
    fixture = HTTPFixtures.register(%{body: "ok"})
    session = session_for_html(:playwright, "<h1>Events</h1>")
    pending = wait_for(session, Event.response())
    visit(session, HTTPFixtures.url(fixture, "/first"))
    visit(session, HTTPFixtures.url(fixture, "/second"))
    assert String.ends_with?(PlaywrightEx.Response.url(await(pending)), "/first")
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
      page = Session.page_state(session).page
      listeners = response_listeners(page)

      owner =
        spawn(fn ->
          pending = wait_for(session, Event.response())
          send(parent, {:pending, pending})

          receive do
            :finish -> exit(unquote(reason))
          end
        end)

      assert_receive {:pending, pending}
      assert response_listeners(page) == listeners + 1
      monitor = Process.monitor(pending.pid)
      send(owner, :finish)
      assert_receive {:DOWN, ^monitor, :process, _, _}
      assert response_listeners(page) == listeners
    end
  end

  test "cancelling one wait retains another and is idempotent" do
    fixture = HTTPFixtures.register(%{body: "ok"})
    session = session_for_html(:playwright, "<h1>Events</h1>")
    first = wait_for(session, Event.response())
    second = wait_for(session, Event.response())
    Subscription.cancel(first.pid)
    Subscription.cancel(first.pid)
    visit(session, HTTPFixtures.url(fixture))
    assert PlaywrightEx.Response.status(await(second)) == 200
  end

  test "settled response metadata survives source closure before await" do
    fixture = HTTPFixtures.register(%{status: 201, body: "ok"})
    session = session_for_html(:playwright, "<h1>Events</h1>")
    pending = wait_for(session, Event.response())
    visit(session, HTTPFixtures.url(fixture))
    assert_eventually(fn -> :sys.get_state(pending.pid).outcome != nil end)
    close_page(session)
    assert PlaywrightEx.Response.status(await(pending)) == 201
  end

  test "source closure and crash resolve outstanding waits" do
    session = session_for_html(:playwright, "<h1>Events</h1>")
    pending = wait_for(session, Event.response())
    close_page(session)
    assert_raise ExUnit.AssertionError, ~r/closed/, fn -> await(pending) end

    session = session_for_html(:playwright, "<h1>Crash signal</h1>")
    pending = wait_for(session, Event.download())
    # Feed the actual protocol lifecycle signal without crashing the shared browser.
    send(pending.pid, {:fluffy_playwright_event, :crash, Session.page_state(session).page})
    assert_raise ExUnit.AssertionError, ~r/crashed/, fn -> await(pending) end
  end

  test "a settled wait releases managed subscriptions before its value is consumed" do
    fixture = HTTPFixtures.register(%{body: "ok"})
    session = session_for_html(:playwright, "<h1>Events</h1>")
    page = Session.page_state(session).page
    listeners = response_listeners(page)
    pending = wait_for(session, Event.response())
    visit(session, HTTPFixtures.url(fixture))
    assert_eventually(fn -> :sys.get_state(pending.pid).outcome != nil end)
    assert response_listeners(page) == listeners
    Subscription.cancel(pending.pid)
    refute Process.alive?(pending.pid)
  end

  test "page discovery and event decoding retain one page subscription" do
    fixture = HTTPFixtures.register(%{body: "ok"})
    session = session_for_html(:playwright, "<h1>Main</h1>")
    # PlaywrightEx keeps a close listener of its own; compare against the first page.
    close_listeners = EventEmitter.listener_count(Session.page_state(session).page, "close")
    page_wait = wait_for(session, Event.page())
    page = new_page(session)
    assert await(page_wait) == page
    session = switch_page(session, page)

    first = wait_for(session, Event.response())
    second = wait_for(session, Event.response())
    visit(session, HTTPFixtures.url(fixture))
    response = await(first)
    assert await(second) == response
    assert response_page(session, response) == current_page(session)

    assert EventEmitter.listener_count(Session.page_state(session).page, "close") == close_listeners
    assert length(pages(session)) == 2
  end

  defp response_page(session, response) do
    page(session, response |> PlaywrightEx.Response.frame() |> PlaywrightEx.Frame.page())
  end

  defp response_listeners(page), do: EventEmitter.listener_count(page, "response")

  defp assert_eventually(fun, attempts \\ 100)
  defp assert_eventually(fun, 0), do: assert(fun.())

  defp assert_eventually(fun, attempts) do
    if !fun.() do
      Process.sleep(10)
      assert_eventually(fun, attempts - 1)
    end
  end
end
