defmodule Fluffy.Backend.Playwright.Document do
  @moduledoc false

  # Document identity and LiveView navigation bookkeeping live in the page.
  # A context init script stamps each document; one probe reads the stamp, the
  # URL and the LiveView navigations recorded since a cursor.
  # Page timers may be faked and paused (`Fluffy.Playwright.Clock.install/2`), so
  # these scripts never wait on them, and waits poll through Playwright's own.

  alias Fluffy.Backend.Playwright.Bounded
  alias Fluffy.Deadline
  alias PlaywrightEx.Frame
  alias PlaywrightEx.JSHandle

  # What Fluffy's own browser calls around an operation may take: the operation's
  # timeout, but at least a second. A sub-second timeout limits the operation; a
  # merely busy browser should not fail these.
  @min_bookkeeping_timeout 1_000

  @state """
  (() => {
    if (window.__fluffy) return window.__fluffy
    const state = {document: Math.random().toString(36).slice(2) + performance.timeOrigin, navigations: []}
    Object.defineProperty(window, '__fluffy', {value: state, configurable: true})

    window.addEventListener('phx:page-loading-start', event => {
      const {kind, to} = event.detail ?? {}
      if (kind === 'patch' || kind === 'redirect') state.navigations.push({kind, to, complete: false})
    })

    window.addEventListener('phx:page-loading-stop', event => {
      const {kind, to} = event.detail ?? {}
      const pending = [...state.navigations].reverse().find(candidate =>
        !candidate.complete && candidate.kind === kind && candidate.to === to
      )
      if (pending) pending.complete = true
    })

    return state
  })()
  """

  # A document the init script did not reach (a page's initial about:blank) is
  # stamped by its first probe. A redirect since the cursor replaced the view
  # even when a patch followed it (the new view patching on mount).
  @probe """
  cursor => {
    const state = #{@state}
    const recent = cursor == null ? [] : state.navigations.slice(cursor)
    const redirected = recent.some(navigation => navigation.kind === 'redirect')
    return {
      url: location.href,
      document: state.document,
      cursor: state.navigations.length,
      kind: redirected ? 'redirect' : recent.at(-1)?.kind ?? 'document'
    }
  }
  """

  # Fluffy can adopt a document right after it commits, such as after an
  # action's navigation, before the body is parsed. Without the readyState
  # check, the `every` over its LiveView roots would pass with none found yet.
  @live_view_ready """
  () => document.readyState !== 'loading' &&
      Array.from(document.querySelectorAll('[data-phx-main], [data-phx-session]'))
    .every(element => {
      // Parent patches can remove a nested view's phx-connected class.
      // Read the bound view without requiring a window.liveSocket global.
      const view = element.phxPrivate?.view
      if (typeof view?.isConnected === 'function' && typeof view?.isJoinPending === 'function') {
        return view.isConnected() && !view.isJoinPending()
      }
      return element.classList.contains('phx-connected')
    })
  """

  def init_script, do: @state

  def bookkeeping_timeout(:infinity), do: :infinity
  def bookkeeping_timeout(timeout) when is_integer(timeout), do: max(timeout, @min_bookkeeping_timeout)

  @doc "A page listener that flags the state when its main frame navigates."
  def navigation_listener(state) do
    guid = state.frame.guid
    navigated = state.navigated
    fn frame -> if frame.guid == guid, do: :atomics.put(navigated, 1, 1) end
  end

  @doc "Whether the main frame may have navigated since Fluffy last read the document it adopted."
  def navigated?(state), do: :atomics.get(state.navigated, 1) == 1

  @doc """
  Like `probe!/3`, for a read whose document Fluffy then adopts. Clearing the
  flag first misses no navigation that commits after the read; a failed read
  adopts nothing, so the flag stays set.
  """
  def adopted_probe!(state, cursor, timeout) do
    navigated = :atomics.exchange(state.navigated, 1, 0)

    try do
      probe!(state.frame, cursor, timeout)
    catch
      kind, reason ->
        if navigated == 1, do: :atomics.put(state.navigated, 1, 1)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc """
  Reads the frame's document identity, URL and LiveView navigations since `cursor`.

  `evaluate` has no timeout and waits while a script blocks the page's main
  thread, so the read gives up after `timeout`.
  """
  def probe!(frame, cursor, timeout), do: probe!(frame, cursor, timeout, Deadline.new(timeout), 5)

  defp probe!(frame, cursor, timeout, deadline, backoff) do
    case Bounded.within(Deadline.remaining(deadline, 1), fn -> Frame.evaluate(frame, @probe, cursor) end) do
      {:ok, {:ok, %{"url" => url, "document" => document, "cursor" => next, "kind" => kind}}} ->
        %{url: url, document: document, cursor: next, kind: kind(kind)}

      # A navigation replaced the execution context mid-call; read the new one.
      # A redirect chain (a page that navigates on load) replaces several, so
      # back off rather than call the driver in a busy loop.
      {:ok, {:error, error}} ->
        if context_destroyed?(error) do
          remaining = Deadline.remaining(deadline)
          Process.sleep(if remaining == :infinity, do: backoff, else: min(backoff, remaining))
        end

        if context_destroyed?(error) and not Deadline.expired?(deadline),
          do: probe!(frame, cursor, timeout, deadline, min(backoff * 2, 50)),
          else: raise(error)

      :timeout ->
        raise "the page did not respond to Fluffy's document check within #{timeout}ms; " <>
                "a script may be blocking its main thread, or a dialog (alert, confirm) may be waiting " <>
                "to be accepted or dismissed"
    end
  end

  @doc """
  Whether a call failed because a navigation replaced the document it ran in.

  Playwright reports it only by message, the same for every browser.
  """
  def context_destroyed?(error),
    do: Exception.message(error) =~ "Execution context was destroyed, most likely because of a navigation"

  def wait_for_live_view!(frame, destination, timeout) do
    case Frame.wait_for_function(frame, @live_view_ready, nil, timeout: timeout) do
      {:ok, handle} ->
        release(handle)

      {:error, %PlaywrightEx.TargetClosedError{} = error} ->
        raise error

      {:error, error} ->
        raise "LiveView browser connection failed for #{inspect(destination)}: expected every LiveView root " <>
                "to be connected with its join complete, got: " <> Exception.message(error)
    end
  end

  def wait_for_redirect!(frame, destination, cursor, timeout) do
    expression = """
    cursor => window.__fluffy?.navigations
      .slice(cursor)
      .some(event => event.kind === 'redirect' && event.complete)
    """

    case Frame.wait_for_function(frame, expression, cursor, timeout: timeout) do
      {:ok, handle} ->
        release(handle)

      {:error, %PlaywrightEx.TargetClosedError{} = error} ->
        raise error

      {:error, error} ->
        raise "LiveView browser navigation failed for #{inspect(destination)}: expected redirect completion " <>
                "before [data-phx-main].phx-connected, got: " <> Exception.message(error)
    end
  end

  # LiveView starts a navigation synchronously but can change the URL after the
  # action has returned. Read the final state only once that navigation
  # finishes, including redirects that keep the URL or replace the document.
  def wait_for_navigations!(frame, cursor, timeout) do
    expression = "cursor => window.__fluffy?.navigations.slice(cursor).every(event => event.complete) ?? true"

    case Frame.wait_for_function(frame, expression, cursor, timeout: timeout) do
      {:ok, handle} -> release(handle)
      {:error, %PlaywrightEx.TargetClosedError{} = error} -> raise error
      {:error, error} -> raise "LiveView browser navigation did not complete: " <> Exception.message(error)
    end
  end

  # A wait returns a handle to its truthy result, which lives as long as the
  # document unless disposed. Nothing awaits the dispose.
  def release(handle) do
    {:ok, _pid} = Task.Supervisor.start_child(Fluffy.TaskSupervisor, fn -> JSHandle.dispose(handle) end)
    :ok
  end

  defp kind("patch"), do: :patch
  defp kind("redirect"), do: :redirect
  defp kind(_document), do: :document
end
