defmodule Fluffy.Backend do
  @moduledoc false

  alias Fluffy.Driver.Registry, as: DriverRegistry
  alias Fluffy.Internal.OperationFailure
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

  @doc """
  Runs `operation` on the driver of the session's active page and resolves its result
  (`Fluffy.Driver.Contract`): a navigation it reports is the backend's to perform, and
  a continuation then runs on the page it landed on, with this function to dispatch
  again. Calls go down only: a driver hands navigation back instead of calling up.
  """
  def driver(%Session{} = session, operation, arguments) do
    driver = DriverRegistry.module(Session.current_driver(session))
    driver.validate_operation!(session, operation, arguments)
    driver |> apply(operation, [session | arguments]) |> resolve_driver_result()
  rescue
    error -> reraise(OperationFailure.normalize(session, operation, arguments, error), __STACKTRACE__)
  end

  defp resolve_driver_result(%Session{} = session), do: session

  defp resolve_driver_result({:return, result, outcome}) do
    resolve_driver_result(outcome)
    result
  end

  defp resolve_driver_result({:navigate, %Session{} = session, navigation}), do: navigate(session, navigation)

  defp resolve_driver_result({:navigate, %Session{} = session, navigation, continue}) when is_function(continue, 2),
    do: session |> navigate(navigation) |> continue.(&driver/3)

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
      reraise OperationFailure.navigation(session, operation, error), __STACKTRACE__

    error in Fluffy.CapabilityError ->
      reraise Fluffy.CapabilityError.put_call(error, operation, session), __STACKTRACE__
  end

  defp session_options(options, :phoenix) do
    endpoint = option(options, :endpoint)

    if is_nil(endpoint) do
      raise ArgumentError, """
      Fluffy.start_session/2: missing Fluffy endpoint; configure:

          config :fluffy, endpoint: MyAppWeb.Endpoint

      or pass `endpoint:` to `start_session/2`
      """
    end

    options |> put_base_url() |> Keyword.put(:endpoint, endpoint)
  end

  defp session_options(options, :playwright), do: put_base_url(options)

  defp put_base_url(options) do
    # As Playwright's `baseURL`, from the most specific level. An endpoint's is its `url` config's,
    # on its listener's port.
    base_url =
      options[:base_url] || endpoint_url(options[:endpoint]) || Fluffy.TestInfo.fetch!().use[:base_url] ||
        endpoint_url(Application.get_env(:fluffy, :endpoint))

    if is_nil(base_url) do
      raise ArgumentError, """
      Fluffy.start_session/2: missing Fluffy base URL; configure either:

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

  # The endpoint's configured URL (`struct_url/0`, whose host Phoenix's `check_origin` and the
  # app's own absolute URLs use), with the scheme and port of its running listener, so `port: 0`
  # works. The HTTP listener first: a test's HTTPS one often has a self-signed certificate.
  defp endpoint_url(endpoint) do
    url = endpoint.struct_url()

    url =
      case Enum.find_value([:http, :https], &listener_port(endpoint, &1)) do
        {scheme, port} -> %{url | scheme: Atom.to_string(scheme), port: port}
        nil -> url
      end

    URI.to_string(url)
  end

  defp listener_port(endpoint, scheme) do
    case endpoint.server_info(scheme) do
      {:ok, {_address, port}} when is_integer(port) and port > 0 -> {scheme, port}
      _other -> nil
    end
  rescue
    _error -> nil
  catch
    _kind, _reason -> nil
  end
end
