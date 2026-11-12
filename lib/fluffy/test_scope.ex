defmodule Fluffy.TestScope do
  @moduledoc false

  # A test's Fluffy state, in the test process. Teardown is `on_exit` callbacks, which
  # ExUnit runs in reverse order after the test process exits, also when it fails: each
  # session closes (browser contexts, in-process LiveViews) before the application's
  # sandbox owners stop, as its DataCase registered their `on_exit` first.

  alias Fluffy.SessionRuntime

  @process_key {__MODULE__, :current}

  @type t :: %{sandbox_header: {String.t(), String.t()} | nil, test_context: map()}
  @type attachment :: {pid(), {String.t(), String.t()} | nil, map()}

  def setup(context) when is_map(context) do
    if current(), do: raise(ArgumentError, "Fluffy.Test.setup has already been called for this test")

    # The whole map, with ExUnit's `test_pid`, for PlaywrightEx.Test (a `parameterize:`
    # module's values pick its owner).
    Process.put(@process_key, %{sandbox_header: Fluffy.Sandbox.metadata_header(self()), test_context: context})
    :ok
  end

  @spec current() :: t() | nil
  def current, do: Process.get(@process_key)

  @spec attach_session() :: attachment()
  def attach_session do
    case current() do
      %{sandbox_header: sandbox_header, test_context: test_context} ->
        {start_runtime(), sandbox_header, test_context}

      nil ->
        raise ArgumentError,
              "add `use Fluffy.Test` (or call Fluffy.Test.setup(context)) before Fluffy.start_session/1,2"
    end
  end

  # A runtime of the calling process, closed when the test ends if it is a Fluffy test.
  def start_runtime do
    {:ok, runtime} = SessionRuntime.start(self())
    if current(), do: ExUnit.Callbacks.on_exit(fn -> SessionRuntime.close(runtime) end)
    runtime
  end
end
