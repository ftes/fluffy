defmodule Fluffy.Support.ModuleTimesFormatter do
  @moduledoc """
  An ExUnit formatter that appends each test module's wall time (`setup_all` included) to the
  file named by `FLUFFY_MODULE_TIMES_FILE` (if set), one `milliseconds<TAB>file<TAB>module` line
  per module. CI prints the slowest: `mix test --slowest-modules` would force `--trace`, which
  runs one module at a time without timeouts.

  It also touches `FLUFFY_MODULE_FAILURES_FILE` (if set) on a module-level failure. A
  `setup_all` teardown can fail after every test passes, leaving nothing for `--failed` to rerun.
  """
  use GenServer

  @impl true
  def init(_opts) do
    times_path = System.get_env("FLUFFY_MODULE_TIMES_FILE", "")
    failures_path = System.get_env("FLUFFY_MODULE_FAILURES_FILE", "")
    {:ok, {times_path, failures_path, %{}}}
  end

  @impl true
  def handle_cast({:module_started, %ExUnit.TestModule{} = module}, {times_path, failures_path, started}) do
    {:noreply, {times_path, failures_path, Map.put(started, module.name, System.monotonic_time(:millisecond))}}
  end

  def handle_cast({:module_finished, %ExUnit.TestModule{} = module}, {times_path, failures_path, started}) do
    if failures_path != "" and match?({:failed, _}, module.state), do: File.touch!(failures_path)

    {start, started} = Map.pop!(started, module.name)

    if times_path != "" do
      ms = System.monotonic_time(:millisecond) - start
      File.write!(times_path, "#{ms}\t#{Path.relative_to_cwd(module.file)}\t#{inspect(module.name)}\n", [:append])
    end

    {:noreply, {times_path, failures_path, started}}
  end

  def handle_cast(_event, state), do: {:noreply, state}
end
