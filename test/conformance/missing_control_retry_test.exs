defmodule Fluffy.Conformance.MissingControlRetryTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  if System.get_env("FLUFFY_REPRO") != "1" do
    @moduletag skip: "Set FLUFFY_REPRO=1 to run the missing-control retry reproduction"
  end

  for driver <- Drivers.backends() do
    @tag driver: driver
    test "to_be_enabled waits for a button to mount with #{driver}", %{driver: driver} do
      session = driver |> start_session() |> visit("/live/async?delay=1000")
      button = by_role(:button, name: "Appeared", exact: true)
      expect(session, to_have_count(button, 0), timeout: 500)

      started = System.monotonic_time(:millisecond)

      try do
        expect(session, to_be_enabled(button), timeout: 3_000)
      after
        elapsed = System.monotonic_time(:millisecond) - started
        expect(session, to_have_count(button, 1), timeout: 3_000)
        expect(session, to_be_enabled(button), timeout: 500)
        IO.puts("#{driver}: initial count 0; enabled assertion took #{elapsed} ms; later count 1 and enabled")
      end
    end
  end
end
