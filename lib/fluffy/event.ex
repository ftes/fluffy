defmodule Fluffy.Event do
  @moduledoc """
  Event descriptions shared by waits and listeners.

  Constructors accept an optional unary predicate. A false or nil result skips
  the event. Predicates inspect event metadata; use ordinary assertions on the
  awaited value to check its contents.

  Download events support both backends. Other events require Playwright.
  Request and response registrations accept `scope: :page` (the default) or
  `scope: :context`. Page events observe the context; all other events observe
  the page selected when registering.
  """

  alias Fluffy.Event.Pending
  alias Fluffy.Event.Subscription
  alias Fluffy.Session
  alias Fluffy.SessionRuntime

  @types [:download, :popup, :page, :frame_navigated, :dialog, :file_chooser, :request, :response]
  @enforce_keys [:type]
  defstruct [:type, :predicate]

  @type type :: :download | :popup | :page | :frame_navigated | :dialog | :file_chooser | :request | :response
  @type t :: %__MODULE__{type: type(), predicate: (term() -> term()) | nil}
  @type option :: {:timeout, non_neg_integer()} | {:scope, :page | :context}

  for type <- @types do
    @doc "Describes a #{type} event, optionally filtered by a unary predicate."
    @spec unquote(type)((term() -> term()) | nil) :: t()
    def unquote(type)(predicate \\ nil) when is_nil(predicate) or is_function(predicate, 1) do
      %__MODULE__{type: unquote(type), predicate: predicate}
    end
  end

  @doc false
  def wait(session, event, options) do
    {source, options} = registration(session, event, options, :wait)
    timeout = Keyword.get(options, :timeout, Session.context(session).timeout)
    deadline = Fluffy.Deadline.new(timeout)
    pid = Subscription.start(session, event, source, :wait, nil, deadline)
    Pending.new(pid)
  end

  @doc false
  def listen(session, event, handler, options, mode) when is_function(handler, 1) do
    {source, _options} = registration(session, event, options, :listener)
    Subscription.start(session, event, source, mode, handler, nil)
    session
  end

  @doc false
  def off(session, event, handler, options) when is_function(handler, 1) do
    {source, _options} = registration(session, event, options, :listener)

    case SessionRuntime.remove_listener(session.runtime, source, event.type, handler) do
      {:ok, nil} -> :ok
      {:ok, pid} -> Subscription.remove(pid)
      {:error, message} -> raise ArgumentError, message
    end

    session
  end

  @doc false
  def expect(session, event, action, assertion, options) when is_function(action, 1) do
    pending = wait(session, event, options)

    try do
      action.(session)
      value = Pending.await(pending)
      if assertion, do: assertion.(value)
      session
    after
      Pending.cancel(pending)
    end
  end

  defp registration(session, %__MODULE__{type: type, predicate: predicate}, options, mode)
       when type in @types and (is_nil(predicate) or is_function(predicate, 1)) do
    schema = if mode == :wait, do: [timeout: [type: :non_neg_integer]], else: []
    schema = if type in [:request, :response], do: schema ++ [scope: [type: {:in, [:page, :context]}]], else: schema
    options = NimbleOptions.validate!(options, schema)
    source = Session.backend(session).event_source(session, type, Keyword.get(options, :scope, :page))
    {source, options}
  end
end
