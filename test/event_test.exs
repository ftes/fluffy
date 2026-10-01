defmodule Fluffy.EventTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect

  alias Fluffy.Event
  alias Fluffy.SessionRuntime

  setup do
    [session: Fluffy.Backend.static_html_session("<p>Events</p>")]
  end

  test "independent waits can observe one event, consume once, and reuse values", %{session: session} do
    a = wait_for(session, Event.download())
    b = wait_for(session, Event.download())
    emit(session, :downloaded)
    assert await(a) == :downloaded
    value = await(b)
    assert value == :downloaded
    assert value == :downloaded
    assert_raise ArgumentError, ~r/already consumed/, fn -> await(a) end
  end

  test "predicates skip false and nil; failures propagate only through await", %{session: session} do
    pending = wait_for(session, Event.download(&(&1 == :match)))
    emit(session, :skip)
    emit(session, :match)
    assert await(pending) == :match

    pending = wait_for(session, Event.download(fn _ -> raise "predicate failed" end))
    emit(session, :anything)
    assert_raise RuntimeError, "predicate failed", fn -> await(pending) end
  end

  test "deadlines start at registration and settled outcomes survive closure", %{session: session} do
    expired = wait_for(session, Event.download(), timeout: 0)
    assert_raise ExUnit.AssertionError, ~r/timeout/, fn -> await(expired) end

    settled = wait_for(session, Event.download())
    emit(session, :captured)
    # A call ordered after event delivery establishes that it was processed.
    :sys.get_state(settled.pid)
    close_session(session)
    assert await(settled) == :captured
  end

  test "pending waits report source and session closure", %{session: session} do
    pending = wait_for(session, Event.download())
    SessionRuntime.close_page(session.runtime, session.active_page)
    assert_raise ExUnit.AssertionError, ~r/page is closed/, fn -> await(pending) end

    session = Fluffy.Backend.static_html_session("<p>Second session</p>")
    pending = wait_for(session, Event.download())
    close_session(session)
    assert_raise ExUnit.AssertionError, ~r/session is closed/, fn -> await(pending) end
  end

  for helper <- [&Fluffy.Expect.expect_event/3, &Fluffy.Assert.assert_event/3] do
    test "#{inspect(helper)} registers before the action and ignores its return", %{session: session} do
      helper = unquote(helper)
      owner = self()

      assert helper.(session, Event.download(), fn input ->
               assert self() == owner
               assert input == session
               emit(input, :value)
               :ignored
             end) == session
    end
  end

  test "all assertion/options forms run callbacks once in the caller", %{session: session} do
    owner = self()

    action = fn input ->
      assert self() == owner
      send(owner, :action)
      emit(input, :value)
      :ignored
    end

    assertion = fn value ->
      assert self() == owner
      assert value == :value
      send(owner, :assertion)
      :ignored
    end

    for {module, function} <- [{Fluffy.Expect, :expect_event}, {Fluffy.Assert, :assert_event}] do
      assert apply(module, function, [session, Event.download(), action, [timeout: 100]]) == session
      assert_receive :action
      assert apply(module, function, [session, Event.download(), action, assertion]) == session
      assert_receive :action
      assert_receive :assertion
      assert apply(module, function, [session, Event.download(), action, assertion, [timeout: 100]]) == session
      assert_receive :action
      assert_receive :assertion
    end

    refute_receive :action
    refute_receive :assertion
  end

  test "events may arrive after the action returns", %{session: session} do
    expect_event(
      session,
      Event.download(),
      fn input ->
        spawn(fn -> emit(input, :later) end)
      end,
      fn value -> assert value == :later end
    )
  end

  test "callback failures preserve their exception and release registrations", %{session: session} do
    assert_raise RuntimeError, "action failed", fn ->
      expect_event(session, Event.download(), fn _ -> raise "action failed" end)
    end

    assert :sys.get_state(session.runtime).subscriptions == []

    assert_raise RuntimeError, "assertion failed", fn ->
      expect_event(session, Event.download(), &emit(&1, :value), fn _ -> raise "assertion failed" end)
    end

    assert :sys.get_state(session.runtime).subscriptions == []

    assert_raise RuntimeError, "closed", fn ->
      expect_event(session, Event.download(), fn input ->
        close_session(input)
        raise "closed"
      end)
    end
  end

  test "listeners are ordered, independently registered, and removed one at a time", %{session: session} do
    owner = self()
    handler = fn value -> send(owner, {:value, value}) end
    on(session, Event.download(), handler)
    on(session, Event.download(), handler)
    emit(session, 1)
    assert_receive {:value, 1}
    assert_receive {:value, 1}
    off(session, Event.download(fn _ -> false end), handler)
    emit(session, 2)
    assert_receive {:value, 2}
    refute_receive {:value, 2}
    off(session, Event.download(), handler)
    emit(session, 3)
    refute_receive {:value, 3}
  end

  test "once removes itself before invocation and does not require occurrence", %{session: session} do
    owner = self()

    once(session, Event.download(&(&1 == :match)), fn value ->
      assert :sys.get_state(session.runtime).subscriptions == []
      send(owner, {:once, value})
    end)

    emit(session, :skip)
    emit(session, :match)
    emit(session, :match)
    assert_receive {:once, :match}
    refute_receive {:once, _}
    assert once(session, Event.download(), fn _ -> flunk("unexpected event") end) == session
  end

  test "invalid scopes and unsupported events fail before registering", %{session: session} do
    assert_raise NimbleOptions.ValidationError, fn -> wait_for(session, Event.download(), scope: :context) end
    assert_raise Fluffy.CapabilityError, fn -> wait_for(session, Event.dialog()) end
    assert :sys.get_state(session.runtime).subscriptions == []
  end

  test "blocked handlers do not delay other listeners or owner cleanup", %{session: session} do
    parent = self()

    {owner, owner_ref} =
      spawn_monitor(fn ->
        on(session, Event.download(), fn value ->
          send(parent, {:blocked, self(), value})

          receive do
            :release -> :ok
          end
        end)

        send(parent, :registered)

        receive do
          :finish -> :ok
        end
      end)

    assert_receive :registered
    on(session, Event.download(), fn value -> send(parent, {:independent, value}) end)
    emit(session, :value)
    assert_receive {:blocked, handler, :value}
    handler_ref = Process.monitor(handler)
    assert_receive {:independent, :value}
    send(owner, :finish)
    assert_receive {:DOWN, ^owner_ref, :process, ^owner, :normal}
    assert_receive {:DOWN, ^handler_ref, :process, ^handler, :killed}
  end

  @tag capture_log: true
  test "listener handler and predicate failures fail their registering caller", %{session: session} do
    for kind <- [:handler, :predicate] do
      parent = self()

      {owner, ref} =
        spawn_monitor(fn ->
          predicate = if kind == :predicate, do: fn _ -> raise "listener failed" end
          handler = fn _ -> raise "listener failed" end
          on(session, Event.download(predicate), handler)
          send(parent, :registered)

          receive do
            :never -> :ok
          end
        end)

      assert_receive :registered
      emit(session, :value)
      assert_receive {:DOWN, ^ref, :process, ^owner, {%RuntimeError{message: "listener failed"}, _stack}}
    end
  end

  test "off removes the most recent matching handler regardless of predicates", %{session: session} do
    owner = self()
    handler = fn value -> send(owner, {:value, value}) end
    on(session, Event.download(&(&1 == :first)), handler)
    on(session, Event.download(&(&1 == :second)), handler)
    off(session, Event.download(), handler)
    emit(session, :first)
    emit(session, :second)
    assert_receive {:value, :first}
    refute_receive {:value, :second}
  end

  test "off removes future delivery without interrupting the current handler", %{session: session} do
    owner = self()

    handler = fn value ->
      send(owner, {:handling, self(), value})

      receive do
        :finish -> :ok
      end

      send(owner, :completed)
    end

    on(session, Event.download(), handler)
    emit(session, :first)
    assert_receive {:handling, worker, :first}
    off(session, Event.download(), handler)
    emit(session, :second)
    send(worker, :finish)
    assert_receive :completed
    refute_receive {:handling, _, :second}
  end

  test "scoped events preserve in-process changes despite ignored action returns" do
    session = Fluffy.Backend.static_html_session("<input aria-label='Name'>")

    expect_event(session, Event.download(), fn input ->
      Fluffy.fill(input, Fluffy.Locator.by_label("Name"), "Ada")
      emit(input, :value)
      :ignored
    end)

    expect(session, "Name" |> Fluffy.Locator.by_label() |> to_have_value("Ada"))
  end

  defp emit(session, value), do: SessionRuntime.emit_event(session.runtime, session.active_page, :download, value)
end
