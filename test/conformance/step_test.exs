defmodule Fluffy.Conformance.StepTest do
  use Fluffy.Support.Case, async: true

  import Fluffy

  alias Fluffy.Support.Server
  alias Fluffy.Support.Web.Endpoint

  # The trace's steps: Fluffy.PlaywrightArtifactsTest.
  for {driver, backend, path} <- [
        {:static, :phoenix, "/chamber"},
        {:live, :phoenix, "/live/three-heads"},
        {:playwright, :playwright, "/live/three-heads"}
      ] do
    test "returns the callback's session from nested steps with #{driver}" do
      session =
        unquote(backend)
        |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
        |> step("Approach Fluffy", fn session ->
          step(session, "Tiptoe in", &visit(&1, unquote(path)), box: true)
        end)

      assert Fluffy.Session.current_driver(session) == unquote(driver)
    end
  end

  test "a boxed step reports its error at the call of the function it is in" do
    session = start_session(:phoenix, endpoint: Endpoint)

    stacktrace =
      try do
        wake_fluffy(session)
      rescue
        _ -> __STACKTRACE__
      end

    assert [{_module, _fun, _arity, location} | _] = stacktrace
    assert Path.expand(to_string(location[:file])) == __ENV__.file

    assert __ENV__.file |> File.read!() |> String.split("\n") |> Enum.at(location[:line] - 1) |> String.trim() ==
             "wake_fluffy(session)"
  end

  test "requires the callback to return a session and rejects unknown options" do
    session = start_session(:phoenix, endpoint: Endpoint)

    assert_raise ArgumentError, ~r/must return a Fluffy.Session, got: :ok/, fn ->
      step(session, "Feed Fluffy", fn _session -> :ok end)
    end

    assert_raise ArgumentError, ~r/unknown keys \[:location\]/, fn ->
      step(session, "Feed Fluffy", & &1, location: %{})
    end
  end

  # Without `use Fluffy.Case`, nothing records steps: the callback just runs.
  defp wake_fluffy(session) do
    step(session, "Stop the music", fn _session -> raise "Fluffy wakes up" end, box: true)
    :awake
  end
end

defmodule Fluffy.Conformance.StepTest.Unregistered do
  @moduledoc false
  use ExUnit.Case, async: true

  import Fluffy

  test "runs the callback outside a registered test" do
    session =
      :phoenix
      |> start_session(endpoint: Fluffy.Support.Web.Endpoint)
      |> step("Sneak past Fluffy", &visit(&1, "/chamber"))

    assert Fluffy.Session.current_driver(session) == :static
  end
end
