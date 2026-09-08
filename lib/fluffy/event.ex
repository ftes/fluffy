defmodule Fluffy.Event do
  @moduledoc """
  Typed event-wait values and event capture orchestration.

  Download events accept:

  #{NimbleOptions.docs(Fluffy.Options.download_event_schema())}

  Dialog events accept:

  #{NimbleOptions.docs(Fluffy.Options.dialog_event_schema())}

  File-chooser, popup, navigation, request, and response events accept
  the shared timeout option:

  #{NimbleOptions.docs(Fluffy.Options.action_schema())}
  """

  import ExUnit.Assertions

  alias Fluffy.Backend
  alias Fluffy.Options
  alias Fluffy.Session

  @enforce_keys [:type, :key]
  defstruct [:type, :key, options: []]

  @type type ::
          :dialog | :download | :file_chooser | :navigation | :page | :request | :response
  @type t :: %__MODULE__{type: type(), key: term(), options: keyword()}
  @type timeout_option :: unquote(NimbleOptions.option_typespec(Options.action_schema()))
  @type download_option :: unquote(NimbleOptions.option_typespec(Options.download_event_schema()))
  @type dialog_option :: unquote(NimbleOptions.option_typespec(Options.dialog_event_schema()))
  @type network_option :: unquote(NimbleOptions.option_typespec(Options.network_event_schema()))
  @type option :: timeout_option() | download_option() | dialog_option() | network_option()

  @spec download(term(), [download_option()]) :: t()
  def download(key, options \\ []) do
    new(:download, key, Options.validate_event_constructor!(:download, options))
  end

  @doc "Captures the browser file chooser opened by the action."
  @spec file_chooser(term(), [timeout_option()]) :: t()
  def file_chooser(key, options \\ []) do
    new(:file_chooser, key, Options.validate_event_constructor!(:file_chooser, options))
  end

  @doc "Captures a new page opened by the action. Requires Playwright."
  @spec popup(term(), [timeout_option()]) :: t()
  def popup(key, options \\ []) do
    new(:page, key, Options.validate_event_constructor!(:page, options))
  end

  @spec navigation(term(), [timeout_option()]) :: t()
  def navigation(key, options \\ []) do
    new(:navigation, key, Options.validate_event_constructor!(:navigation, options))
  end

  @spec dialog(term(), [dialog_option()]) :: t()
  def dialog(key, options \\ []) do
    options = Options.validate_event_constructor!(:dialog, options)
    {decision, options} = pop_dialog_decision!(options)
    new(:dialog, key, Keyword.put(options, :decision, decision))
  end

  @spec request(term(), String.t() | Regex.t() | (term() -> boolean()), [timeout_option()]) :: t()
  def request(key, matcher, options \\ []) do
    options = Options.validate_event_constructor!(:request, options)
    new(:request, key, Keyword.put(options, :matcher, matcher))
  end

  @spec response(term(), String.t() | Regex.t() | (term() -> boolean()), [timeout_option()]) :: t()
  def response(key, matcher, options \\ []) do
    options = Options.validate_event_constructor!(:response, options)
    new(:response, key, Keyword.put(options, :matcher, matcher))
  end

  @doc false
  def new(type, key, options) when type in [:dialog, :download, :file_chooser, :navigation, :page, :request, :response] do
    %__MODULE__{type: type, key: key, options: Options.validate_event!(type, options)}
  end

  @doc false
  def merge_options(%__MODULE__{type: type, options: event_options} = event, options) when is_list(options) do
    merged =
      type
      |> default_options()
      |> Keyword.merge(event_options)
      |> Keyword.merge(options)
      |> then(&Options.validate_event!(type, &1))

    %{event | options: merged}
  end

  @doc false
  def capture(%Session{} = session, type, key, action, options \\ []) when is_atom(type) and is_function(action, 1) do
    options = Options.validate_event!(type, options)
    timeout = Keyword.get(options, :timeout, default_timeout(session))

    deadline = System.monotonic_time(:millisecond) + timeout
    {session, token} = Session.arm_event(session, type, key, options)

    arm_options =
      options
      |> Keyword.put(:deadline, deadline)
      |> Keyword.put(:timeout, remaining(deadline))

    {:ok, armed_session, resource} = Backend.arm_event(session, type, arm_options)

    try do
      action_session = action.(armed_session)
      ensure_action_session!(action_session, armed_session.backend, token)
      remaining = remaining(deadline)

      case Backend.await_event(action_session, resource, remaining) do
        {:ok, updated_session, value} ->
          Session.put_result(updated_session, token, value)

        {:error, :timeout} ->
          flunk("Expected #{inspect(type)} event #{inspect(key)} within #{timeout} ms, but no matching event occurred")

        {:error, reason} ->
          flunk("Could not capture #{inspect(type)} event #{inspect(key)}: #{inspect(reason)}")
      end
    after
      :ok = Backend.disarm_event(session.backend, resource)
    end
  end

  defp ensure_action_session!(%Session{backend: backend} = session, backend, token) do
    case Session.pending_event(session) do
      %{token: ^token} -> :ok
      _missing -> raise ArgumentError, "event action must return the updated session it receives"
    end
  end

  defp ensure_action_session!(other, _backend, _token) do
    raise ArgumentError,
          "event action must return a Fluffy.Session, got: #{inspect(other)}"
  end

  defp default_timeout(session) do
    Map.get(session.context, :timeout, Application.get_env(:fluffy, :timeout, 1_000))
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp default_options(:download), do: [max_bytes: 10_000_000]
  defp default_options(_type), do: []

  defp pop_dialog_decision!(options) when is_list(options) do
    cond do
      Keyword.has_key?(options, :decision) ->
        {Keyword.fetch!(options, :decision), Keyword.delete(options, :decision)}

      Keyword.get(options, :accept) == true ->
        {:accept, Keyword.delete(options, :accept)}

      is_binary(Keyword.get(options, :accept)) ->
        {{:accept, Keyword.fetch!(options, :accept)}, Keyword.delete(options, :accept)}

      Keyword.get(options, :dismiss) == true ->
        {:dismiss, Keyword.delete(options, :dismiss)}

      true ->
        {:accept, options}
    end
  end
end
