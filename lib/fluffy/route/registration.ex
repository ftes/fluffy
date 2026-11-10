defmodule Fluffy.Route.Registration do
  @moduledoc false

  # One `Fluffy.Playwright.route/4` call: a native route of the session's context,
  # which lasts until `unroute/3` or the session's end. The listener only starts a
  # process per request, because PlaywrightEx's dispatch must not wait on a handler
  # and the test process is blocked in the action that caused the request. `$callers`
  # runs through the registering caller, so the Ecto sandbox allows the handler.
  # PlaywrightEx's `behavior:` cannot see those processes, so `unroute_all/2` keeps
  # its promise for them: they register under their route's tracker, whose flag
  # tells them to ignore their errors (Playwright's `RouteHandler.stop`).

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
    tracker = :atomics.new(1, [])
    listener = listener(session, tracker, handler, [self() | Process.get(:"$callers", [])])

    SessionRuntime.run_registered(session.runtime, fn ->
      BrowserContext.route!(browser_context, match, listener, Keyword.take(options, [:times]))
      # Closing the context releases the route.
      {:ok, {:route, key(url), handler, match, listener, tracker}, fn -> :ok end}
    end)
  end

  def remove(session, url, handler) do
    browser_context = Session.context(session).browser_context
    key = key(url)
    {:ok, resources} = SessionRuntime.resources(session.runtime)

    for {:route, ^key, registered, match, listener, _tracker} = resource <- resources, handler in [nil, registered] do
      :ok = SessionRuntime.release(session.runtime, resource)
      BrowserContext.unroute!(browser_context, match, listener)
    end
  end

  def remove_all(session, options) do
    browser_context = Session.context(session).browser_context
    {:ok, resources} = SessionRuntime.resources(session.runtime)

    behavior = Keyword.get(options, :behavior, :default)

    # Released first, as in `remove/3`: a timeout below cannot leave them registered.
    trackers =
      for {:route, _key, _handler, _match, _listener, tracker} = resource <- resources do
        :ok = SessionRuntime.release(session.runtime, resource)
        if behavior == :ignore_errors, do: :atomics.put(tracker, 1, 1)
        tracker
      end

    Bounded.within!(Session.timeout(session, options), :unroute_all, fn ->
      # PlaywrightEx waits for the answers; a handler process may still run after its own.
      with :ok <- BrowserContext.unroute_all(browser_context, behavior: behavior) do
        if behavior == :wait, do: Enum.each(trackers, &await_handlers/1)
        {:ok, :ok}
      end
    end)
  end

  defp await_handlers(tracker) do
    for {pid, _value} <- Registry.lookup(Fluffy.Route.Registry, tracker) do
      monitor = Process.monitor(pid)

      receive do
        {:DOWN, ^monitor, :process, _pid, _reason} -> :ok
      end
    end
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

  defp listener(session, tracker, handler, [owner | _] = callers) do
    fn native, request ->
      {:ok, _pid} =
        Task.Supervisor.start_child(Fluffy.TaskSupervisor, fn ->
          Process.put(:"$callers", callers)
          {:ok, _owner} = Registry.register(Fluffy.Route.Registry, tracker, nil)
          run(session, tracker, handler, native, request, owner)
        end)

      :ok
    end
  end

  defp run(session, tracker, handler, native, request, owner) do
    handler.(%Route{request: Events.request(session, request), native: native})
  catch
    kind, reason when kind != :exit or reason != :normal ->
      cond do
        # `unroute_all(behavior: :ignore_errors)`: as in Playwright, the request goes on.
        :atomics.get(tracker, 1) == 1 ->
          PlaywrightEx.Route.fallback(native)

        # The session, page or context went away under the handler.
        not Process.alive?(session.runtime) or is_struct(reason, PlaywrightEx.TargetClosedError) ->
          :ok

        true ->
          PlaywrightEx.Route.abort(native, "failed")
          Process.exit(owner, {Exception.normalize(kind, reason, __STACKTRACE__), __STACKTRACE__})
      end
  end
end
