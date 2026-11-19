defmodule Fluffy.Backend do
  @moduledoc false

  alias Fluffy.Session

  def start_session(name, options) when is_list(options) do
    options = name |> Fluffy.Options.validate_session!(options) |> session_options(name)
    Fluffy.Backend.Registry.module(name).start_session(options)
  end

  @doc false
  def static_html_session(html) when is_binary(html) do
    Fluffy.Backend.Phoenix.session_for_html(html)
  end

  def close_session(%Session{} = session), do: Fluffy.SessionRuntime.close(session.runtime)

  def new_page(session), do: dispatch(session, :new_page, [])
  def history(session, direction, options), do: navigation!(session, direction, :history, [direction, options])
  def visit(session, destination), do: navigation!(session, :visit, :visit, [destination])
  def reload(session, options), do: navigation!(session, :reload, :reload, [options])

  def navigate(session, navigation) do
    dispatch(session, :navigate, [navigation])
  end

  def close_page(session, page_id) do
    dispatch(session, :close_page, [page_id])
  end

  def absolute_url(session, path), do: Session.backend(session).absolute_url(session, path)
  def base_url(session), do: dispatch(session, :base_url, [])

  def add_cookies(session, cookies), do: dispatch(session, :add_cookies, [cookies])
  def cookies(session, urls), do: dispatch(session, :cookies, [urls])
  def clear_cookies(session, options), do: dispatch(session, :clear_cookies, [options])

  def page_snapshot(runtime, record), do: dispatch_page(runtime, record, :page_snapshot)

  defp dispatch_page(runtime, record, operation) do
    case Fluffy.SessionRuntime.configuration(runtime) do
      {:ok, {backend, context}} -> apply(backend, operation, [context, record])
      {:error, message} -> raise ArgumentError, message
    end
  end

  defp dispatch(session, operation, args) do
    apply(Session.backend(session), operation, [session | args])
  end

  # As for an action, Playwright's error, which keeps Playwright's call log, becomes the
  # cause of a `Fluffy.OperationError`, as do a navigation Fluffy found failed and a
  # LiveView that failed on the way.
  defp navigation!(session, operation, callback, args) do
    dispatch(session, callback, args)
  rescue
    error in [
      Fluffy.Internal.NavigationFailure,
      Fluffy.LiveViewError,
      Playwright.PlaywrightError,
      Playwright.TimeoutError,
      Playwright.TargetClosedError
    ] ->
      reraise Fluffy.Internal.OperationFailure.navigation(session, operation, error), __STACKTRACE__
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

    options |> put_base_url() |> Keyword.put(:endpoint, endpoint)
  end

  defp session_options(options, :playwright), do: put_base_url(options)

  defp put_base_url(options) do
    # As Playwright's `baseURL`, from the most specific level. An endpoint's is its listener's.
    base_url =
      options[:base_url] || endpoint_url(options[:endpoint]) || Fluffy.TestInfo.fetch!().use[:base_url] ||
        endpoint_url(Application.get_env(:fluffy, :endpoint))

    if is_nil(base_url) do
      raise ArgumentError, """
      missing Fluffy base URL; configure either:

          config :fluffy, endpoint: MyAppWeb.Endpoint

      or:

          config :playwright, :test, base_url: "http://localhost:4002"

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
