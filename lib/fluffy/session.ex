defmodule Fluffy.Session do
  @moduledoc """
  The opaque state threaded through Fluffy test pipelines.

  Sessions are created and operated through the functions in `Fluffy` and
  backend-specific public helpers such as `Fluffy.Playwright`. Their fields
  and state-transition functions are internal implementation details.
  """

  alias Fluffy.Backend.Phoenix
  alias Fluffy.Backend.Phoenix.Context
  alias Fluffy.Backend.Playwright
  alias Fluffy.Page

  @enforce_keys [:backend, :context, :pages, :active_page]
  defstruct [:backend, :context, :pages, :active_page, :pending_event, results: %{}]

  @typedoc "An opaque Fluffy session handle."
  @opaque t :: %__MODULE__{
            backend: Phoenix | Playwright,
            context: Context.t() | Fluffy.Backend.Playwright.Context.t(),
            pages: %{required(term()) => Page.t()},
            active_page: term(),
            pending_event: map() | nil,
            results: map()
          }

  @doc false
  def new(backend, context, %Page{id: page_id} = page) do
    %__MODULE__{
      backend: backend,
      context: context,
      pages: %{page_id => page},
      active_page: page_id
    }
  end

  @doc false
  def current_page(%__MODULE__{} = session), do: Map.fetch!(session.pages, session.active_page)

  @doc false
  def current_driver(%__MODULE__{} = session), do: current_page(session).driver

  @doc false
  def backend(%__MODULE__{} = session), do: session.backend

  @doc false
  def context(%__MODULE__{} = session), do: session.context

  @doc false
  def put_context(%__MODULE__{} = session, context), do: %{session | context: context}

  @doc false
  def page_state(%__MODULE__{} = session), do: current_page(session).state

  @doc false
  def put_page_state(%__MODULE__{} = session, state) do
    update_current_page(session, &%{&1 | state: state})
  end

  @doc false
  def put_page_opener(%__MODULE__{} = session, opener) do
    update_current_page(session, &%{&1 | opener: opener})
  end

  @doc false
  def put_page_status(%__MODULE__{} = session, status) do
    update_current_page(session, &%{&1 | status: status})
  end

  @doc false
  def commit_page(%__MODULE__{} = session, driver, state, url, options \\ []) do
    update_current_page(session, &Page.commit(&1, driver, state, url, options))
  end

  @doc false
  def put_page(%__MODULE__{} = session, %Page{id: page_id} = page) do
    if Map.has_key?(session.pages, page_id) do
      raise ArgumentError, "page name #{inspect(page_id)} is already in use"
    end

    %{session | pages: Map.put(session.pages, page_id, page)}
  end

  @doc false
  def activate_page(%__MODULE__{} = session, page_id) do
    if Map.has_key?(session.pages, page_id) do
      %{session | active_page: page_id}
    else
      raise ArgumentError, "no page named #{inspect(page_id)} exists in this session"
    end
  end

  @doc false
  def delete_page(%__MODULE__{} = session, page_id, fallback_page) do
    pages = Map.delete(session.pages, page_id)

    if !Map.has_key?(pages, fallback_page) do
      raise ArgumentError,
            "cannot close page #{inspect(page_id)} without a remaining fallback page"
    end

    active_page = if session.active_page == page_id, do: fallback_page, else: session.active_page
    %{session | pages: pages, active_page: active_page}
  end

  @doc false
  def arm_event(%__MODULE__{pending_event: nil} = session, type, key, options) do
    if Map.has_key?(session.results, key) do
      raise ArgumentError,
            "captured result key #{inspect(key)} is already in use; event result keys are immutable within a session"
    end

    token = make_ref()

    {%{session | pending_event: %{token: token, type: type, key: key, options: options}}, token}
  end

  def arm_event(%__MODULE__{pending_event: pending}, _type, _key, _options) do
    raise ArgumentError,
          "cannot start an event expectation while #{inspect(pending.type)} #{inspect(pending.key)} is pending"
  end

  @doc false
  def pending_event(%__MODULE__{pending_event: pending}), do: pending

  @doc false
  def capture_pending_event(%__MODULE__{pending_event: %{token: token} = pending} = session, token, value) do
    %{session | pending_event: Map.put(pending, :captured, value)}
  end

  def capture_pending_event(%__MODULE__{}, token, _value) do
    raise ArgumentError, "event token #{inspect(token)} is no longer pending"
  end

  @doc false
  def put_result(%__MODULE__{pending_event: %{token: token}} = session, token, value) do
    key = session.pending_event.key
    type = session.pending_event.type

    %{
      session
      | pending_event: nil,
        results: Map.put(session.results, key, %{type: type, value: value})
    }
  end

  def put_result(%__MODULE__{}, token, _value) do
    raise ArgumentError, "event token #{inspect(token)} is no longer pending"
  end

  @doc false
  def fetch_result!(%__MODULE__{} = session, key, expected_type) do
    case Map.fetch(session.results, key) do
      {:ok, %{type: ^expected_type, value: value}} ->
        value

      {:ok, %{type: actual_type}} ->
        raise ArgumentError,
              "captured result #{inspect(key)} contains #{inspect(actual_type)}, expected #{inspect(expected_type)}"

      :error ->
        raise ArgumentError, "no captured result exists under #{inspect(key)}"
    end
  end

  defp update_current_page(%__MODULE__{} = session, fun) do
    %{session | pages: Map.update!(session.pages, session.active_page, fun)}
  end
end
