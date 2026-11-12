defmodule Fluffy.TestScope do
  @moduledoc false

  # A test's Fluffy state, in the test process. Teardown is `on_exit` callbacks, which
  # ExUnit runs in reverse order after the test process exits, also when it fails: each
  # session closes (browser contexts, in-process LiveViews), then the sandbox owners stop.

  alias Ecto.Adapters.SQL.Sandbox
  alias Fluffy.SessionRuntime

  @process_key {__MODULE__, :current}

  @type t :: %{owners: [pid()], sandbox_header: {String.t(), String.t()} | nil, test_context: map()}
  @type attachment :: {pid(), {String.t(), String.t()} | nil, map()}

  def setup(context, options) when is_map(context) and is_list(options) do
    if current(), do: raise(ArgumentError, "Fluffy.Test.setup has already been called for this test")

    {owners, sandbox_header} = acquire_sandbox(Keyword.fetch!(options, :sandbox))
    # Registered before any session's, so it runs after them.
    if owners != [], do: ExUnit.Callbacks.on_exit(fn -> Enum.each(owners, &stop_sandbox_owner/1) end)

    # The whole map, with ExUnit's `test_pid`, for PlaywrightEx.Test (a `parameterize:`
    # module's values pick its owner).
    Process.put(@process_key, %{owners: owners, sandbox_header: sandbox_header, test_context: context})
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

  if Code.ensure_loaded?(Sandbox) do
    defp stop_sandbox_owner(owner) do
      Sandbox.stop_owner(owner)
    rescue
      _reason -> :ok
    catch
      _kind, _reason -> :ok
    end
  else
    defp stop_sandbox_owner(_owner), do: :ok
  end

  defp acquire_sandbox(false), do: {[], nil}
  defp acquire_sandbox({module, function, arguments}), do: apply(module, function, arguments)
end
