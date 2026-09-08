defmodule Fluffy.Backend.Contract do
  @moduledoc false

  alias Fluffy.Navigation
  alias Fluffy.Session
  alias Fluffy.TestScope

  @callback start_session(keyword(), TestScope.attachment()) :: Session.t()
  @callback close_session(Session.t()) :: :ok | {:error, term()}
  @callback visit(Session.t(), String.t()) :: Session.t()
  @callback reload(Session.t(), keyword()) :: Session.t()
  @callback navigate(Session.t(), Navigation.t()) :: Session.t()
  @callback activate_page(Session.t(), term()) :: Session.t()
  @callback close_page(Session.t(), term()) :: Session.t()
  @callback arm_event(Session.t(), atom(), keyword()) :: {:ok, Session.t(), term()}
  @callback await_event(Session.t(), term(), non_neg_integer()) ::
              {:ok, Session.t(), term()} | {:error, term()}
  @callback disarm_event(term()) :: :ok
  @callback run_step(Session.t(), String.t(), keyword(), (-> term())) :: term()
  @callback capture_failure(Session.t(), atom(), Exception.t(), Exception.stacktrace()) :: term()
  @callback absolute_url(Session.t(), String.t()) :: String.t()
end
