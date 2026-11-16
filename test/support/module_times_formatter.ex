defmodule Fluffy.Support.ModuleTimesFormatter do
  @moduledoc """
  An ExUnit formatter that appends each test module's wall time (`setup_all` included) to the
  file named by `FLUFFY_MODULE_TIMES_FILE` (if set), one `milliseconds<TAB>file<TAB>module` line
  per module. CI prints the slowest: `mix test --slowest-modules` would force `--trace`, which
  runs one module at a time without timeouts.
  """
  use GenServer

  @impl true
  def init(_opts), do: {:ok, {System.get_env("FLUFFY_MODULE_TIMES_FILE", ""), %{}}}

  @impl true
  def handle_cast(_event, {"", _started} = state), do: {:noreply, state}

  def handle_cast({:module_started, %ExUnit.TestModule{} = module}, {path, started}) do
    {:noreply, {path, Map.put(started, module.name, System.monotonic_time(:millisecond))}}
  end

  def handle_cast({:module_finished, %ExUnit.TestModule{} = module}, {path, started}) do
    {start, started} = Map.pop!(started, module.name)
    ms = System.monotonic_time(:millisecond) - start
    File.write!(path, "#{ms}\t#{Path.relative_to_cwd(module.file)}\t#{inspect(module.name)}\n", [:append])
    {:noreply, {path, started}}
  end

  def handle_cast(_event, state), do: {:noreply, state}
end
