defmodule Fluffy.SessionRuntimeTest do
  use ExUnit.Case, async: true

  alias Fluffy.SessionRuntime

  test "event routing respects source and type, and removal is idempotent" do
    session = Fluffy.session_for_html(:static, "<p>Events</p>")
    runtime = session.runtime
    assert :ok = SessionRuntime.subscribe(runtime, self(), session.active_page, :download, nil)
    SessionRuntime.emit_event(runtime, :context, :download, :wrong_source)
    SessionRuntime.emit_event(runtime, session.active_page, :response, :wrong_type)
    refute_receive {:fluffy_event, _}
    SessionRuntime.emit_event(runtime, session.active_page, :download, :matching)
    assert_receive {:fluffy_event, :matching}
    assert :ok = SessionRuntime.unsubscribe(runtime, self())
    assert :ok = SessionRuntime.unsubscribe(runtime, self())
    SessionRuntime.emit_event(runtime, session.active_page, :download, :removed)
    refute_receive {:fluffy_event, _}
    assert {:error, _} = SessionRuntime.subscribe(runtime, self(), make_ref(), :download, nil)
  end

  test "page errors leave the runtime usable" do
    session = Fluffy.session_for_html(:static, "<input aria-label='Name'>")
    runtime = session.runtime
    assert {:error, _} = SessionRuntime.page(runtime, make_ref())
    assert {:error, _} = SessionRuntime.put_page_state(runtime, make_ref(), %{})
    assert {:error, _} = SessionRuntime.resolve(runtime, Fluffy.Page.new(runtime, make_ref()))
    assert {:ok, page} = SessionRuntime.page(runtime, session.active_page)
    assert {:error, _} = SessionRuntime.replace_page(runtime, %{page | id: make_ref()})
    Fluffy.fill(session, Fluffy.Locator.by_label("Name"), "Ada")
    Fluffy.Expect.expect(session, Fluffy.Expect.to_have_value(Fluffy.Locator.by_label("Name"), "Ada"))
  end

  test "cleanup unwinds acquired resources and continues after a failure" do
    {:ok, runtime} = SessionRuntime.start(self())
    caller = self()
    SessionRuntime.register(runtime, :first, fn -> send(caller, :first_closed) end)
    SessionRuntime.register(runtime, :released, fn -> send(caller, :released_closed) end)
    SessionRuntime.release(runtime, :released)

    SessionRuntime.register(runtime, :last, fn ->
      send(caller, :last_closed)
      raise "cleanup failed"
    end)

    assert SessionRuntime.resources(runtime) == {:ok, [:last, :first]}
    assert :ok = SessionRuntime.close(runtime)
    assert_received first
    assert first == :last_closed
    assert_received second
    assert second == :first_closed
    refute_received :released_closed
  end

  test "state survives discarded handles and session shutdown is idempotent" do
    session = Fluffy.session_for_html(:static, "<input aria-label='Name'>")
    Fluffy.fill(session, Fluffy.Locator.by_label("Name"), "Ada")
    Fluffy.Expect.expect(session, Fluffy.Expect.to_have_value(Fluffy.Locator.by_label("Name"), "Ada"))
    assert :ok = Fluffy.Backend.close_session(session)
    assert :ok = Fluffy.Backend.close_session(session)
    assert_raise ArgumentError, ~r/session is closed/, fn -> Fluffy.Session.context(session) end
  end

  test "normal owner exit releases its runtime and resources" do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, runtime} = SessionRuntime.start(self())
        {:ok, resource} = Agent.start(fn -> nil end)
        SessionRuntime.register(runtime, resource, fn -> Agent.stop(resource) end)
        send(parent, {:started, runtime, resource})

        receive do
          :finish -> :ok
        end
      end)

    assert_receive {:started, runtime, resource}
    monitor = Process.monitor(runtime)
    send(owner, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^runtime, :normal}
    refute Process.alive?(resource)
  end

  test "owner failure releases its runtime and resources" do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, runtime} = SessionRuntime.start(self())
        {:ok, resource} = Agent.start(fn -> nil end)
        SessionRuntime.register(runtime, resource, fn -> Agent.stop(resource) end)
        send(parent, {:started, runtime, resource})
        Process.sleep(:infinity)
      end)

    assert_receive {:started, runtime, resource}
    monitor = Process.monitor(runtime)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^runtime, :normal}
    refute Process.alive?(resource)
  end
end
