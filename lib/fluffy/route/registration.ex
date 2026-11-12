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

  alias Fluffy.Backend.Playwright.Events
  alias Fluffy.Route
  alias Fluffy.Session
  alias Fluffy.SessionRuntime
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Isomorphic.UrlMatch

  def start(session, url, handler, options) do
    browser_context = Session.context(session).browser_context
    validate!(url)
    tracker = :atomics.new(1, [])
    listener = listener(session, tracker, handler, [self() | Process.get(:"$callers", [])])

    SessionRuntime.run_registered(session.runtime, fn ->
      BrowserContext.route!(browser_context, url, listener, Keyword.take(options, [:times]))
      # Closing the context releases the route.
      {:ok, {:route, url, handler, listener, tracker}, fn -> :ok end}
    end)
  end

  def remove(session, url, handler) do
    browser_context = Session.context(session).browser_context
    {:ok, resources} = SessionRuntime.resources(session.runtime)

    # As in Playwright, which compares a regular expression by source and flags.
    for {:route, registered_url, registered, listener, _tracker} = resource <- resources,
        UrlMatch.url_matches_equal(registered_url, url),
        handler in [nil, registered] do
      :ok = SessionRuntime.release(session.runtime, resource)
      BrowserContext.unroute!(browser_context, registered_url, listener)
    end
  end

  def remove_all(session, options) do
    browser_context = Session.context(session).browser_context
    {:ok, resources} = SessionRuntime.resources(session.runtime)

    behavior = Keyword.get(options, :behavior, :default)

    # Released first, as in `remove/3`: a failure below cannot leave them registered.
    trackers =
      for {:route, _url, _handler, _listener, tracker} = resource <- resources do
        :ok = SessionRuntime.release(session.runtime, resource)
        if behavior == :ignore_errors, do: :atomics.put(tracker, 1, 1)
        tracker
      end

    # PlaywrightEx waits for the answers; a handler process may still run after its own.
    case BrowserContext.unroute_all(browser_context, behavior: behavior) do
      :ok -> if behavior == :wait, do: Enum.each(trackers, &await_handlers/1)
      {:error, error} -> raise error
    end
  end

  defp await_handlers(tracker) do
    for {pid, _value} <- Registry.lookup(Fluffy.Route.Registry, tracker) do
      monitor = Process.monitor(pid)

      receive do
        {:DOWN, ^monitor, :process, _pid, _reason} -> :ok
      end
    end
  end

  defp validate!(url) when is_binary(url) or is_struct(url, Regex) or is_function(url, 1), do: :ok

  defp validate!(url) do
    raise ArgumentError, "expected a route URL to be a glob, regex or predicate, got: #{inspect(url)}"
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

        # The session ended under the handler, as at the end of a test.
        not Process.alive?(session.runtime) ->
          :ok

        true ->
          PlaywrightEx.Route.abort(native, "failed")
          Process.exit(owner, {kind |> Exception.normalize(reason, __STACKTRACE__) |> hint(), __STACKTRACE__})
      end
  end

  # As in Playwright, a handler that its page or context closed under gets a hint.
  defp hint(%PlaywrightEx.TargetClosedError{} = error) do
    %{
      error
      | message:
          ~s("#{error.message}" while running route callback.\n) <>
            "Consider calling `Fluffy.Playwright.unroute_all(session, behavior: :ignore_errors)`\n" <>
            "before the end of the test to ignore remaining routes in flight."
    }
  end

  defp hint(error), do: error
end
