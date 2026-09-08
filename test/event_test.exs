defmodule Fluffy.EventTest do
  use Fluffy.TestCase, async: true

  alias Fluffy.Event
  alias Fluffy.Page
  alias Fluffy.Session

  defmodule FakeBackend do
    @moduledoc false
    @behaviour Fluffy.Backend.Contract

    def start_session(_options, _attachment), do: raise("not used")
    def close_session(_session), do: :ok
    def visit(_session, _path), do: raise("not used")
    def reload(_session, _options), do: raise("not used")
    def navigate(_session, _navigation), do: raise("not used")
    def activate_page(_session, _page_id), do: raise("not used")
    def close_page(_session, _page_id), do: raise("not used")
    def absolute_url(_session, path), do: path
    def run_step(_session, _name, _location, fun), do: fun.()
    def capture_failure(_session, _operation, _error, _stacktrace), do: :ok

    def arm_event(session, type, options) do
      probe = Keyword.fetch!(options, :probe)
      send(probe, {:armed, type})
      {:ok, session, probe}
    end

    def await_event(session, probe, timeout) do
      send(probe, {:awaited, timeout})
      {:ok, session, %{captured: true}}
    end

    def disarm_event(probe) do
      send(probe, :disarmed)
      :ok
    end
  end

  test "arms before running the action, runs it once, stores the result, and disarms" do
    session = session()
    Process.put(:event_action_count, 0)

    session =
      Event.capture(
        session,
        :fake,
        :observation,
        fn session ->
          assert_receive {:armed, :fake}
          Process.put(:event_action_count, Process.get(:event_action_count) + 1)
          session
        end,
        probe: self(),
        timeout: 100
      )

    assert Process.get(:event_action_count) == 1
    assert_receive {:awaited, remaining} when remaining <= 100
    assert_receive :disarmed
    assert Session.fetch_result!(session, :observation, :fake) == %{captured: true}
  end

  test "always disarms when the action fails" do
    assert_raise RuntimeError, "action failed", fn ->
      Event.capture(
        session(),
        :fake,
        :failure,
        fn _session ->
          raise "action failed"
        end,
        probe: self()
      )
    end

    assert_receive :disarmed
  end

  test "rejects a duplicate result key before arming or running the action" do
    session = Event.capture(session(), :fake, :same, & &1, probe: self())
    assert_receive {:armed, :fake}
    assert_receive {:awaited, _remaining}
    assert_receive :disarmed

    refute_receive :action_ran

    assert_raise ArgumentError, ~r/already in use/, fn ->
      Event.capture(
        session,
        :fake,
        :same,
        fn session ->
          send(self(), :action_ran)
          session
        end,
        probe: self()
      )
    end

    refute_receive :action_ran
    refute_receive {:armed, _type}
  end

  test "requires the action to return its updated session" do
    assert_raise ArgumentError, ~r/must return the updated session/, fn ->
      Event.capture(
        session(),
        :fake,
        :invalid,
        fn session ->
          %{session | pending_event: nil}
        end,
        probe: self()
      )
    end

    assert_receive :disarmed
  end

  defp session do
    page = %Page{id: :main, driver: :static, state: %{}}
    Session.new(FakeBackend, %{timeout: 100}, page)
  end
end
