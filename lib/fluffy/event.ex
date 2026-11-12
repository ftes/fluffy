defmodule Fluffy.Event do
  @moduledoc """
  Event descriptions shared by waits and listeners.

      session
      |> assert_event(
        Fluffy.Event.download(),
        &click(&1, by_role(:link, name: "Download the Marauder's Map"))
      )

  Constructors accept an optional unary predicate. A false or nil result skips
  the event. Predicates inspect event metadata; use ordinary assertions on the
  awaited value to check its contents.

      Fluffy.Event.response(&String.ends_with?(PlaywrightEx.Response.url(&1), "/owls"))

  Download events support both backends. Other events require Playwright.
  Network events (`request`, `response`, `request_failed` and `request_finished`)
  accept `scope: :page` (the default) or `scope: :context`. Page events observe
  the context; all other events observe the page selected when registering. A
  close event resolves with that page's handle, which is closed. As in
  Playwright, an event of a page that closed before Fluffy saw it, such as a
  popup that closes at once, carries that page's closed handle; a request's page
  is then nil.

  `load`, `dom_content_loaded`, `crash`, `popup`, `page` and `close` resolve with
  a `Fluffy.Page`, `download` with a `Fluffy.Download` and `file_chooser` with a
  `Fluffy.FileChooser`. The other events resolve with PlaywrightEx's values, as in
  Playwright: a `PlaywrightEx.Request`, `PlaywrightEx.Response`, `PlaywrightEx.Dialog`,
  `PlaywrightEx.ConsoleMessage`, `PlaywrightEx.Frame`, `PlaywrightEx.Worker`,
  `PlaywrightEx.WebSocket`, or the error of a `page_error`. Read them with
  PlaywrightEx's functions, such as `PlaywrightEx.Response.status/1`, and turn
  their page into a `Fluffy.Page` with `Fluffy.Playwright.page/2`. A crash resolves
  `crash` and fails the page's other waits, except `close`.
  """

  alias Fluffy.Event.Pending
  alias Fluffy.Event.Subscription
  alias Fluffy.Session
  alias Fluffy.SessionRuntime

  @network_types [:request, :response, :request_failed, :request_finished]
  @types ~w(download popup page close load dom_content_loaded crash frame_navigated frame_attached frame_detached
            dialog file_chooser console page_error worker web_socket)a ++ @network_types
  @enforce_keys [:type]
  defstruct [:type, :predicate]

  @doc false
  defguard is_network_type(type) when type in @network_types

  @type type ::
          :download
          | :popup
          | :page
          | :close
          | :load
          | :dom_content_loaded
          | :crash
          | :frame_navigated
          | :frame_attached
          | :frame_detached
          | :dialog
          | :file_chooser
          | :console
          | :page_error
          | :worker
          | :web_socket
          | :request
          | :response
          | :request_failed
          | :request_finished
  @type t :: %__MODULE__{type: type(), predicate: (term() -> term()) | nil}
  @type option :: {:timeout, timeout()} | {:scope, :page | :context}

  for type <- @types do
    @doc playwright_only: type != :download
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
    schema = if mode == :wait, do: [timeout: [type: :timeout]], else: []
    schema = if type in @network_types, do: schema ++ [scope: [type: {:in, [:page, :context]}]], else: schema
    options = NimbleOptions.validate!(options, schema)
    source = Session.backend(session).event_source(session, type, Keyword.get(options, :scope, :page))
    {source, options}
  end
end
