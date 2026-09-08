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
    start_session(name, options, :unmanaged)
  end

  @doc false
  def static_html_session(html) when is_binary(html) do
    Fluffy.Backend.Phoenix.session_for_html(html)
  end

  def close_session(%Session{backend: backend} = session) do
    backend.close_session(session)
  end

  def visit(%Session{backend: backend} = session, destination) do
    backend.visit(session, destination)
  end

  def reload(%Session{backend: backend} = session, options) do
    backend.reload(session, options)
  end

  def navigate(%Session{backend: backend} = session, navigation) do
    backend.navigate(session, navigation)
  end

  def activate_page(%Session{backend: backend} = session, page_id) do
    backend.activate_page(session, page_id)
  end

  def close_page(%Session{backend: backend} = session, page_id) do
    backend.close_page(session, page_id)
  end

  def arm_event(%Session{backend: backend} = session, type, options) do
    backend.arm_event(session, type, options)
  end

  def await_event(%Session{backend: backend} = session, resource, timeout) do
    backend.await_event(session, resource, timeout)
  end

  def disarm_event(backend, resource), do: backend.disarm_event(resource)

  def run_step(%Session{backend: backend} = session, name, location, fun) do
    backend.run_step(session, name, location, fun)
  end

  def capture_failure(%Session{backend: backend} = session, operation, error, stacktrace) do
    backend.capture_failure(session, operation, error, stacktrace)
  end

  def absolute_url(%Session{backend: backend} = session, path), do: backend.absolute_url(session, path)

  defp start_session(name, options, attachment) do
    options = name |> Fluffy.Options.validate_session!(options) |> session_options(name)
    backend = Fluffy.Backend.Registry.module(name)
    backend.start_session(options, attachment)
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
