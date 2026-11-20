defmodule Fluffy.Conformance.StepTest do
  use Fluffy.Support.Case, async: true

  import Fluffy

  # The trace's steps: Fluffy.PlaywrightArtifactsTest.
  for {driver, backend, path} <- [
        {:static, :phoenix, "/chamber"},
        {:live, :phoenix, "/live/three-heads"},
        {:playwright, :playwright, "/live/three-heads"}
      ] do
    test "returns the callback's session from nested steps with #{driver}" do
      session =
        unquote(backend)
        |> start_session()
        |> step("Approach Fluffy", fn session ->
          step(session, "Tiptoe in", &visit(&1, unquote(path)), box: true)
        end)

      assert Fluffy.Session.current_driver(session) == unquote(driver)
    end
  end

  test "a boxed step reports its error at the call of the function it is in" do
    session = start_session(:phoenix)

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
    session = start_session(:phoenix)

    assert_raise ArgumentError, ~r/must return a Fluffy.Session, got: :ok/, fn ->
      step(session, "Feed Fluffy", fn _session -> :ok end)
    end

    assert_raise ArgumentError, ~r/unknown keys \[:location\]/, fn ->
      step(session, "Feed Fluffy", & &1, location: %{})
    end
  end

  # Without `use Playwright.Test`, nothing records steps: the callback just runs.
  defp wake_fluffy(session) do
    step(session, "Stop the music", fn _session -> raise "Fluffy wakes up" end, box: true)
    :awake
  end
end
