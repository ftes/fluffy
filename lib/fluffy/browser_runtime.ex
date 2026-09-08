defmodule Fluffy.BrowserRuntime do
  @moduledoc false

  use GenServer

  alias PlaywrightEx.Browser

  defstruct [
    :browser_id,
    :browser_launcher,
    :engine,
    :launch_options,
    :playwright_options,
    :playwright_supervisor,
    :runtime_supervisor,
    :transport_starter,
    :timeout,
    launch_count: 0
  ]

  @opaque t :: %__MODULE__{
            browser_id: String.t() | nil,
            browser_launcher: function(),
            engine: :chromium | :firefox | :webkit,
            launch_options: keyword(),
            playwright_options: keyword(),
            playwright_supervisor: GenServer.name(),
            runtime_supervisor: GenServer.name(),
            transport_starter: function(),
            timeout: timeout(),
            launch_count: non_neg_integer()
          }

  def browser_id(server \\ __MODULE__) do
    GenServer.call(server, :browser_id, :infinity)
  end

  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  def start_link(options) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      timeout: Keyword.fetch!(options, :timeout),
      engine: Keyword.get(options, :engine, :chromium),
      launch_options: Keyword.fetch!(options, :launch_options),
      playwright_options: Keyword.fetch!(options, :playwright_options),
      playwright_supervisor: Keyword.get(options, :playwright_supervisor, PlaywrightEx.Supervisor),
      runtime_supervisor: Keyword.get(options, :runtime_supervisor, Fluffy.BrowserRuntime.Supervisor),
      transport_starter: Keyword.get(options, :transport_starter, &start_transport/3),
      browser_launcher: Keyword.get(options, :browser_launcher, &launch_browser/4)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:browser_id, _from, %__MODULE__{browser_id: nil} = state) do
    :ok =
      state.transport_starter.(
        state.runtime_supervisor,
        state.playwright_supervisor,
        state.playwright_options
      )

    {:ok, browser} =
      state.browser_launcher.(
        state.engine,
        state.playwright_supervisor,
        state.launch_options,
        state.timeout
      )

    state = %{state | browser_id: browser.guid, launch_count: state.launch_count + 1}
    {:reply, browser.guid, state}
  end

  def handle_call(:browser_id, _from, state) do
    {:reply, state.browser_id, state}
  end

  def handle_call(:status, _from, state) do
    {:reply,
     %{
       browser_id: state.browser_id,
       initialized?: not is_nil(state.browser_id),
       launch_count: state.launch_count,
       playwright_supervisor: state.playwright_supervisor
     }, state}
  end

  @impl true
  def terminate(_reason, %{browser_id: nil}), do: :ok

  def terminate(_reason, state) do
    connection = PlaywrightEx.Supervisor.connection_name(state.playwright_supervisor)

    if Process.whereis(connection) do
      Browser.close(state.browser_id, connection: connection, timeout: state.timeout)
    end

    :ok
  end

  defp start_transport(runtime_supervisor, playwright_supervisor, playwright_options) do
    child =
      {PlaywrightEx.Supervisor, Keyword.put(playwright_options, :name, playwright_supervisor)}

    case DynamicSupervisor.start_child(runtime_supervisor, child) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> raise "could not start Playwright transport: #{inspect(reason)}"
    end
  end

  defp launch_browser(engine, playwright_supervisor, launch_options, timeout) do
    connection = PlaywrightEx.Supervisor.connection_name(playwright_supervisor)

    PlaywrightEx.launch_browser(
      engine,
      launch_options
      |> Keyword.put_new(:timeout, timeout)
      |> Keyword.put(:connection, connection)
    )
  end
end
