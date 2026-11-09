defmodule Fluffy.Route.Registration do
  @moduledoc false

  # One `Fluffy.Playwright.route/4` call: a native route of the session's context,
  # which lasts until `unroute/3` or the session's end. The listener only starts a
  # process per request, because PlaywrightEx's dispatch must not wait on a handler
  # and the test process is blocked in the action that caused the request. `$callers`
  # runs through the registering caller, so the Ecto sandbox allows the handler.

  alias Fluffy.Backend.Playwright.Bounded
  alias Fluffy.Backend.Playwright.Events
  alias Fluffy.Route
  alias Fluffy.Session
  alias Fluffy.SessionRuntime
  alias Fluffy.URLMatcher
  alias PlaywrightEx.BrowserContext

  def start(session, url, handler, options) do
    browser_context = Session.context(session).browser_context
    match = match(url)
    listener = listener(session, key(url), handler, [self() | Process.get(:"$callers", [])])

    SessionRuntime.run_registered(session.runtime, fn ->
      BrowserContext.route!(browser_context, match, listener, Keyword.take(options, [:times]))
      # Closing the context releases the route.
      {:ok, {:route, key(url), handler, match, listener}, fn -> :ok end}
    end)
  end

  def remove(session, url, handler) do
    browser_context = Session.context(session).browser_context
    key = key(url)
    {:ok, resources} = SessionRuntime.resources(session.runtime)

    for {:route, ^key, registered, match, listener} = resource <- resources, handler in [nil, registered] do
      :ok = SessionRuntime.release(session.runtime, resource)
      BrowserContext.unroute!(browser_context, match, listener)
    end
  end

  def remove_all(session, options) do
    browser_context = Session.context(session).browser_context
    {timeout, native} = Keyword.split(options, [:timeout])

    Bounded.within!(Session.timeout(session, timeout), :unroute_all, fn ->
      with :ok <- BrowserContext.unroute_all(browser_context, native), do: {:ok, :ok}
    end)

    {:ok, resources} = SessionRuntime.resources(session.runtime)

    for {:route, _key, _handler, _match, _listener} = resource <- resources,
        do: SessionRuntime.release(session.runtime, resource)
  end

  # What `unroute/3` compares: a regular expression's compiled form can differ
  # between two equal sources.
  defp key(%Regex{} = url), do: {:regex, Regex.source(url), Regex.opts(url)}
  defp key(url), do: url

  # Strings and regular expressions go to Playwright, which filters requests in
  # the browser. Fluffy's other URL matchers become predicates over the URL string.
  defp match(url) when is_binary(url) or is_struct(url, Regex), do: url
  defp match(url) when is_function(url, 1), do: &URLMatcher.matches?(url, &1)

  defp match(components) when is_list(components) do
    matcher = URLMatcher.new!(components)
    &URLMatcher.matches?(matcher, &1)
  end

  defp match(url) do
    raise ArgumentError, "expected a route URL to be a glob, regex, predicate or components, got: #{inspect(url)}"
  end

  defp listener(session, key, handler, [owner | _] = callers) do
    fn native, request ->
      {:ok, _pid} =
        Task.Supervisor.start_child(Fluffy.TaskSupervisor, fn ->
          Process.put(:"$callers", callers)
          run(session, key, handler, native, request, owner)
        end)

      :ok
    end
  end

  defp run(session, key, handler, native, request, owner) do
    handler.(%Route{request: Events.request(session, request), native: native})
  catch
    kind, reason when kind != :exit or reason != :normal ->
      if Process.alive?(session.runtime) and not gone?(reason, session, key, handler) do
        PlaywrightEx.Route.abort(native, "failed")
        Process.exit(owner, {Exception.normalize(kind, reason, __STACKTRACE__), __STACKTRACE__})
      end
  end

  # The page or context went away under the handler, or `unroute/3` released its
  # request. While the route is registered, "already handled" is a double answer.
  defp gone?(%PlaywrightEx.TargetClosedError{}, _session, _key, _handler), do: true

  defp gone?(%PlaywrightEx.PlaywrightError{message: message}, session, key, handler) do
    message =~ "Route is already handled!" and not registered?(session, key, handler)
  end

  defp gone?(_reason, _session, _key, _handler), do: false

  defp registered?(session, key, handler) do
    case SessionRuntime.resources(session.runtime) do
      {:ok, resources} -> Enum.any?(resources, &match?({:route, ^key, ^handler, _match, _listener}, &1))
      {:error, _closed} -> false
    end
  end
end
