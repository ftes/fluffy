defmodule Fluffy.Session do
  @moduledoc """
  A live session handle with a local current-page selection.

  Actions commit their state to the session runtime, so existing handles see
  updates even when an action's return is discarded. Retain the returned handle
  when switching pages. Use each session sequentially from its owning test
  process; concurrent use of the same session is unsupported.
  """
  alias Fluffy.Page
  alias Fluffy.SessionRuntime

  @enforce_keys [:runtime, :active_page]
  defstruct [:runtime, :active_page]
  @type t :: %__MODULE__{runtime: pid(), active_page: reference()}

  @doc false
  def new(backend, context, %Page.State{} = page, runtime \\ nil) do
    runtime = runtime || start_runtime()
    id = value!(SessionRuntime.initialize(runtime, backend, context, page))
    %__MODULE__{runtime: runtime, active_page: id}
  end

  @doc false
  def handle(%__MODULE__{runtime: runtime, active_page: id}), do: Page.new(runtime, id)
  @doc false
  def page_handle(session, page), do: Page.new(session.runtime, value!(SessionRuntime.resolve(session.runtime, page)))
  @doc false
  def current_page(session), do: Page.snapshot(handle(session))
  @doc false
  def current_driver(session), do: Page.record(handle(session)).driver
  @doc false
  def backend(session), do: value!(SessionRuntime.backend(session.runtime))
  @doc false
  def context(session), do: value!(SessionRuntime.context(session.runtime))
  @doc false
  def pages(session), do: value!(SessionRuntime.pages(session.runtime))
  @doc false
  def put_context(session, context) do
    value!(SessionRuntime.put_context(session.runtime, context))
    session
  end

  @doc false
  def page_state(session), do: Page.record(handle(session)).state
  @doc false
  def put_page_state(session, state) do
    value!(SessionRuntime.put_page_state(session.runtime, session.active_page, state))
    session
  end

  @doc false
  def commit_page(session, driver, state, url, options \\ []) do
    backend = backend(session)
    page = backend.commit_page(Page.record(handle(session)), driver, state, url, options)
    value!(SessionRuntime.replace_page(session.runtime, page))
    session
  end

  @doc false
  def register_page(session, page) do
    id = value!(SessionRuntime.register_page(session.runtime, page))
    Page.new(session.runtime, id)
  end

  @doc false
  def activate_page(session, page) do
    %{session | active_page: value!(SessionRuntime.resolve(session.runtime, page))}
  end

  defp value!({:ok, value}), do: value
  defp value!(:ok), do: :ok
  defp value!({:error, message}), do: raise(ArgumentError, message)

  defp start_runtime do
    case Fluffy.TestScope.current() do
      scope when is_pid(scope) ->
        {_scope, runtime, _header} = Fluffy.TestScope.attach_session(scope)
        runtime

      nil ->
        {:ok, runtime} = SessionRuntime.start(self())
        runtime
    end
  end
end
