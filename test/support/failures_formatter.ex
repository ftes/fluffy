defmodule Fluffy.Support.FailuresFormatter do
  @moduledoc """
  An ExUnit formatter that appends each failed test to the file named by `FLUFFY_FAILURES_FILE`
  (if set), one `file:line<TAB>module: test name` line per failure (a failed `setup_all` reports
  its module at line 1). CI reports them, as a green retry would otherwise hide them.
  """
  use GenServer

  @impl true
  def init(_opts), do: {:ok, System.get_env("FLUFFY_FAILURES_FILE", "")}

  @impl true
  def handle_cast(_event, "" = path), do: {:noreply, path}

  def handle_cast({:test_finished, %ExUnit.Test{state: {:failed, _}} = test}, path) do
    write(path, "#{Path.relative_to_cwd(test.tags.file)}:#{test.tags.line}", "#{inspect(test.module)}: #{test.name}")
    {:noreply, path}
  end

  def handle_cast({:module_finished, %ExUnit.TestModule{state: {:failed, _}} = module}, path) do
    write(path, "#{Path.relative_to_cwd(module.file)}:1", "#{inspect(module.name)}: setup_all failed")
    {:noreply, path}
  end

  def handle_cast(_event, path), do: {:noreply, path}

  defp write(path, location, name), do: File.write!(path, "#{location}\t#{name}\n", [:append])
end
