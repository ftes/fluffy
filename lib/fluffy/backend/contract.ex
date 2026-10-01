defmodule Fluffy.Backend.Contract do
  @moduledoc false

  alias Fluffy.Internal.Navigation
  alias Fluffy.Page
  alias Fluffy.Session
  alias Fluffy.TestScope

  @callback start_session(keyword(), TestScope.attachment()) :: Session.t()
  @callback new_page(Session.t(), term()) :: Session.t()
  @callback history(Session.t(), :go_back | :go_forward, keyword()) :: Session.t()
  @callback visit(Session.t(), String.t()) :: Session.t()
  @callback reload(Session.t(), keyword()) :: Session.t()
  @callback navigate(Session.t(), Navigation.t()) :: Session.t()
  @callback close_page(Session.t(), term()) :: Session.t()
  @callback arm_event(Session.t(), atom(), keyword()) :: {:ok, Session.t(), term()}
  @callback await_event(Session.t(), term(), non_neg_integer()) ::
              {:ok, Session.t(), term()} | {:error, term()}
  @callback disarm_event(term()) :: :ok
  @callback run_step(Session.t(), String.t(), keyword(), (-> term())) :: term()
  @callback capture_failure(Session.t(), atom(), Exception.t(), Exception.stacktrace()) :: term()
  @callback normalize_error(Session.t(), atom(), list(), Exception.t()) :: Exception.t()
  @callback absolute_url(Session.t(), String.t()) :: String.t()

  # Metadata and document identity belong to the backend that owns the page.
  @callback page_snapshot(term(), Page.State.t()) :: Page.State.t()
  @callback page_status(term(), Page.State.t()) :: non_neg_integer() | nil
  @callback commit_page(Page.State.t(), atom(), term(), String.t() | nil, keyword()) :: Page.State.t()

  # Normalize backend page identities and events before they enter the runtime.
  @type page_registration :: {Page.State.t(), term() | nil, term() | nil}
  @callback prepare_page(term(), Page.State.t(), pid()) :: {:ok, page_registration()} | {:error, String.t()}
  @callback runtime_event(term(), term()) ::
              {:page_opened, page_registration()} | {:page_closed, term()} | :closed | :ignore
end
