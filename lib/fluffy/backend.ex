defmodule Fluffy.Backend do
  @moduledoc false

  alias Fluffy.Session

  def start_session(name, options) when is_list(options) do
    if Keyword.has_key?(options, :scope) do
      raise ArgumentError, "unknown session option :scope"
    end

    attachment = Fluffy.TestScope.attach_session()
    start_session(name, options, attachment)
  end

  @doc false
  def start_unmanaged_session(name, options) when is_list(options) do
    {:ok, runtime} = Fluffy.SessionRuntime.start(self())
    start_session(name, options, {nil, runtime, nil})
  end

  @doc false
  def static_html_session(html) when is_binary(html) do
    Fluffy.Backend.Phoenix.session_for_html(html)
  end

  def close_session(%Session{} = session), do: Fluffy.SessionRuntime.close(session.runtime)

  def new_page(session), do: dispatch(session, :new_page, [])
  def history(session, direction, options), do: dispatch(session, :history, [direction, options])

  def visit(session, destination) do
    dispatch(session, :visit, [destination])
  end

  def reload(session, options) do
    dispatch(session, :reload, [options])
  end

  def navigate(session, navigation) do
    dispatch(session, :navigate, [navigation])
  end

  def close_page(session, page_id) do
    dispatch(session, :close_page, [page_id])
  end

  def run_step(session, name, location, fun) do
    Session.backend(session).run_step(session, name, location, fun)
  end

  def capture_failure(session, operation, error, stacktrace) do
    Session.backend(session).capture_failure(session, operation, error, stacktrace)
  rescue
    # A failed native callback may have closed the session. Diagnostics must
    # never replace the original action error with a runtime lookup error.
    _artifact_error -> :error
  catch
    :exit, _reason -> :error
  end

  def absolute_url(session, path), do: Session.backend(session).absolute_url(session, path)

  def normalize_error(session, operation, arguments, error)
      when is_struct(error, Fluffy.StrictnessError) or is_struct(error, Fluffy.ActionabilityError),
      do: Session.backend(session).normalize_error(session, operation, arguments, error)

  def normalize_error(_session, _operation, _arguments, error), do: error

  def page_snapshot(runtime, record), do: dispatch_page(runtime, record, :page_snapshot)
  def page_status(runtime, record), do: dispatch_page(runtime, record, :page_status)

  defp dispatch_page(runtime, record, operation) do
    case Fluffy.SessionRuntime.configuration(runtime) do
      {:ok, {backend, context}} -> apply(backend, operation, [context, record])
      {:error, message} -> raise ArgumentError, message
    end
  end

  defp dispatch(session, operation, args) do
    apply(Session.backend(session), operation, [session | args])
  end

  defp start_session(name, options, attachment) do
    options = name |> Fluffy.Options.validate_session!(options) |> session_options(name)
    backend = Fluffy.Backend.Registry.module(name)
    backend.start_session(options, attachment)
  rescue
    error ->
      {_scope, runtime, _header} = attachment
      Fluffy.SessionRuntime.close(runtime)
      reraise error, __STACKTRACE__
  end

  defp session_options(options, :phoenix) do
    endpoint = option(options, :endpoint)

    if is_nil(endpoint) do
      raise ArgumentError, """
      missing Fluffy endpoint; configure:

          config :fluffy, endpoint: MyAppWeb.Endpoint

      or pass `endpoint:` to `start_session/2`
      """
    end

    options
    |> Keyword.put(:endpoint, endpoint)
    |> put_base_url(endpoint)
  end

  defp session_options(options, :playwright) do
    put_base_url(options, option(options, :endpoint))
  end

  defp put_base_url(options, endpoint) do
    base_url = option(options, :base_url) || endpoint_url(endpoint)

    if is_nil(base_url) do
      raise ArgumentError, """
      missing Fluffy base URL; configure either:

          config :fluffy, endpoint: MyAppWeb.Endpoint

      or:

          config :fluffy, base_url: "http://localhost:4002"

      or pass `base_url:` to `start_session/2`
      """
    end

    Keyword.put(options, :base_url, base_url)
  end

  defp option(options, key) do
    case Keyword.fetch(options, key) do
      {:ok, value} -> value
      :error -> Application.get_env(:fluffy, key)
    end
  end

  defp endpoint_url(nil), do: nil

  defp endpoint_url(endpoint) do
    active_listener_url(endpoint) || endpoint.url()
  end

  defp active_listener_url(endpoint) do
    if function_exported?(endpoint, :server_info, 1) do
      Enum.find_value([:http, :https], &listener_url(endpoint, &1))
    end
  end

  defp listener_url(endpoint, scheme) do
    case endpoint.server_info(scheme) do
      {:ok, {address, port}} when is_integer(port) and port > 0 ->
        listener_uri(scheme, address, port)

      _other ->
        nil
    end
  rescue
    _error -> nil
  catch
    _kind, _reason -> nil
  end

  defp listener_uri(scheme, address, port) when tuple_size(address) in [4, 8] do
    host = address |> reachable_address() |> :inet.ntoa() |> to_string()
    URI.to_string(%URI{scheme: Atom.to_string(scheme), host: host, port: port})
  end

  defp listener_uri(_scheme, _address, _port), do: nil

  defp reachable_address({0, 0, 0, 0}), do: {127, 0, 0, 1}
  defp reachable_address({0, 0, 0, 0, 0, 0, 0, 0}), do: {0, 0, 0, 0, 0, 0, 0, 1}
  defp reachable_address(address), do: address
end
