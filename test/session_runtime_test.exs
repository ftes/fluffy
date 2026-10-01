defmodule Fluffy.SessionRuntimeTest do
  use ExUnit.Case, async: true

  alias Fluffy.SessionRuntime

  test "the runtime enforces capture tokens, immutable keys, and result types without crashing" do
    {:ok, runtime} = SessionRuntime.start(self())
    {:ok, token} = SessionRuntime.begin_capture(runtime, :popup, :result, [])

    assert {:error, pending_error} = SessionRuntime.begin_capture(runtime, :download, :other, [])
    assert pending_error =~ "is pending"
    assert {:error, _} = SessionRuntime.record_capture(runtime, make_ref(), :wrong)
    assert {:error, _} = SessionRuntime.finish_capture(runtime, make_ref(), :wrong)
    assert :ok = SessionRuntime.record_capture(runtime, token, :first)
    assert {:error, _} = SessionRuntime.record_capture(runtime, token, :second)
    assert {:ok, %{captured: :first}} = SessionRuntime.pending_capture(runtime)
    assert :ok = SessionRuntime.finish_capture(runtime, token, :first)
    assert {:ok, nil} = SessionRuntime.pending_capture(runtime)
    assert {:ok, :first} = SessionRuntime.fetch_result(runtime, :result, :page)
    assert {:error, _} = SessionRuntime.fetch_result(runtime, :result, :download)
    assert {:error, _} = SessionRuntime.fetch_result(runtime, :missing, :page)
    assert {:error, duplicate_error} = SessionRuntime.begin_capture(runtime, :page, :result, [])
    assert duplicate_error =~ "already in use"
    assert {:ok, :first} = SessionRuntime.fetch_result(runtime, :result, :page)
  end

  test "cancelling an old capture cannot cancel its replacement" do
    {:ok, runtime} = SessionRuntime.start(self())
    {:ok, old_token} = SessionRuntime.begin_capture(runtime, :download, :result, [])
    assert :ok = SessionRuntime.cancel_capture(runtime, old_token)
    {:ok, new_token} = SessionRuntime.begin_capture(runtime, :download, :result, [])

    assert :ok = SessionRuntime.cancel_capture(runtime, old_token)
    assert {:error, _} = SessionRuntime.finish_capture(runtime, old_token, :stale)
    assert {:ok, %{token: ^new_token}} = SessionRuntime.pending_capture(runtime)
    assert :ok = SessionRuntime.finish_capture(runtime, new_token, :download)
    assert :ok = SessionRuntime.close(runtime)
    assert {:error, "session is closed"} = SessionRuntime.cancel_capture(runtime, new_token)
  end

  test "page errors leave the runtime usable" do
    session = Fluffy.session_for_html(:static, "<input aria-label='Name'>")
    runtime = session.runtime
    assert {:error, _} = SessionRuntime.page(runtime, make_ref())
    assert {:error, _} = SessionRuntime.put_page_state(runtime, make_ref(), %{})
    assert {:error, _} = SessionRuntime.resolve(runtime, :missing)
    assert {:ok, page} = SessionRuntime.page(runtime, session.active_page)
    assert {:error, _} = SessionRuntime.register_page(runtime, %{page | id: nil})
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
