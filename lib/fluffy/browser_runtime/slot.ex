defmodule Fluffy.BrowserRuntime.Slot do
  @moduledoc false

  # One browser of the pool, in a process of its own: launching blocks this slot
  # and the sessions bound to it, nothing else. The slot stays alive as the
  # browser's creator, which PlaywrightEx anchors the browser's data to.

  use GenServer

  alias Fluffy.Backend.Playwright.Bounded
  alias PlaywrightEx.Browser
  alias PlaywrightEx.BrowserType
  alias PlaywrightEx.Playwright

  @driver Fluffy.PlaywrightDriver

  defstruct [
    :browser,
    :browser_closer,
    :browser_launcher,
    :engine,
    :launch_options,
    :playwright_options,
    :playwright_name,
    :runtime_supervisor,
    :transport_starter,
    :timeout,
    launch_count: 0
  ]

  @opaque t :: %__MODULE__{
            browser: Browser.t() | nil,
            browser_closer: function(),
            browser_launcher: function(),
            engine: :chromium | :firefox | :webkit,
            launch_options: keyword(),
            playwright_options: keyword(),
            playwright_name: atom(),
            runtime_supervisor: GenServer.name(),
            transport_starter: function(),
            timeout: timeout(),
            launch_count: non_neg_integer()
          }

  @doc "Returns the slot's browser, launching it if needed. Raises if it cannot launch."
  def browser(slot) do
    slot |> GenServer.call(:browser, :infinity) |> browser!()
  end

  @doc "Returns a browser other than `lost`, launching one if `lost` is current."
  def replace(slot, lost) do
    slot |> GenServer.call({:replace, lost.guid}, :infinity) |> browser!()
  end

  # A failed launch raises in the session that asked for the browser. Crashing the
  # runtime instead would restart every running session.
  defp browser!({:ok, browser}), do: browser
  defp browser!({:error, error}), do: raise(error)

  def status(slot) do
    GenServer.call(slot, :status, :infinity)
  end

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      timeout: Keyword.fetch!(options, :timeout),
      engine: Keyword.get(options, :engine, :chromium),
      launch_options: Keyword.fetch!(options, :launch_options),
      playwright_options: Keyword.fetch!(options, :playwright_options),
      playwright_name: Keyword.get(options, :playwright_name, @driver),
      runtime_supervisor: Keyword.get(options, :runtime_supervisor, Fluffy.BrowserRuntime.Supervisor),
      transport_starter: Keyword.get(options, :transport_starter, &start_transport/3),
      browser_launcher: Keyword.get(options, :browser_launcher, &launch_browser/3),
      browser_closer: Keyword.get(options, :browser_closer, &Browser.close/1)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:browser, _from, %__MODULE__{browser: nil} = state) do
    case launch(state) do
      {:ok, browser} ->
        state = %{state | browser: browser, launch_count: state.launch_count + 1}
        {:reply, {:ok, browser}, state}

      {:error, reason} ->
        {:reply, {:error, launch_error(state.engine, reason)}, state}
    end
  end

  def handle_call(:browser, _from, state) do
    {:reply, {:ok, state.browser}, state}
  end

  # The lost browser may still run, refusing contexts; close it without
  # holding up the callers waiting for its replacement.
  def handle_call({:replace, guid}, from, %{browser: %{guid: guid} = lost} = state) do
    {:ok, _pid} =
      Task.Supervisor.start_child(Fluffy.TaskSupervisor, fn ->
        Bounded.within(state.timeout, fn -> close_browser(state, lost) end)
      end)

    handle_call(:browser, from, %{state | browser: nil})
  end

  def handle_call({:replace, _guid}, from, state), do: handle_call(:browser, from, state)

  def handle_call(:status, _from, state) do
    {:reply,
     %{
       browser: state.browser,
       launch_count: state.launch_count,
       playwright_name: state.playwright_name
     }, state}
  end

  @impl true
  # A lost driver disconnects every browser. The next session relaunches
  # against the restarted driver's root.
  def handle_info({:browser_disconnected, guid}, %{browser: %{guid: guid}} = state),
    do: {:noreply, %{state | browser: nil}}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{browser: nil}), do: :ok

  def terminate(_reason, state) do
    Bounded.within(state.timeout, fn -> close_browser(state, state.browser) end)
    :ok
  catch
    _kind, _reason -> :ok
  end

  # Shutdown is best effort, and a crash in the unlinked call would only log.
  defp close_browser(state, browser) do
    state.browser_closer.(browser)
  catch
    _kind, _reason -> :ok
  end

  # Invalid launch options raise in PlaywrightEx. That raise belongs to the
  # caller too, not to the runtime.
  defp launch(state) do
    launch_options = Keyword.put_new(state.launch_options, :timeout, state.timeout)

    with :ok <- state.transport_starter.(state.runtime_supervisor, state.playwright_name, state.playwright_options) do
      state.browser_launcher.(state.engine, state.playwright_name, launch_options)
    end
  rescue
    exception -> {:error, exception}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp start_transport(runtime_supervisor, name, playwright_options) do
    child = {PlaywrightEx.Supervisor, Keyword.put(playwright_options, :name, name)}

    case DynamicSupervisor.start_child(runtime_supervisor, child) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, {:transport, reason}}
    end
  end

  defp launch_error(engine, {:transport, reason}),
    do: RuntimeError.exception("could not start the Playwright driver for #{engine}: #{inspect(reason)}")

  defp launch_error(engine, reason) do
    detail = if is_exception(reason), do: Exception.message(reason), else: inspect(reason)
    RuntimeError.exception("could not launch the Playwright #{engine} browser: #{detail}")
  end

  defp launch_browser(engine, name, launch_options) do
    runtime = self()
    browser_type = apply(Playwright, engine, [PlaywrightEx.playwright(name)])

    with {:ok, browser} <- BrowserType.launch(browser_type, launch_options) do
      Browser.on(browser, :disconnected, fn browser -> send(runtime, {:browser_disconnected, browser.guid}) end)
      {:ok, browser}
    end
  end
end
