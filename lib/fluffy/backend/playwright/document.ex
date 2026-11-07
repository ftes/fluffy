defmodule Fluffy.Backend.Playwright.Document do
  @moduledoc false

  # Document identity, LiveView navigation and checkbox activation bookkeeping
  # live in the page.
  # A context init script stamps each document; one probe reads the stamp, the
  # URL and the LiveView navigations recorded since a cursor.
  # Page timers may be faked and paused (`Fluffy.Playwright.install_clock/2`), so
  # these scripts never wait on them, and waits poll through Playwright's own.

  alias Fluffy.Backend.Playwright.Bounded
  alias Fluffy.Deadline
  alias PlaywrightEx.Frame
  alias PlaywrightEx.JSHandle
  alias PlaywrightEx.Locator

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

    // What the last trusted click did to a checkbox or radio, before page code
    // (such as a LiveView patch) can change it again.
    state.activations = {count: 0, checked: null}
    window.addEventListener('input', ({isTrusted, target}) => {
      if (isTrusted && target instanceof HTMLInputElement && ['checkbox', 'radio'].includes(target.type))
        state.activations = {count: state.activations.count + 1, checked: target.checked}
    }, true)

    return state
  })()
  """

  # A document the init script did not reach (a page's initial about:blank) is
  # stamped by its first probe.
  @probe """
  cursor => {
    const state = #{@state}
    const recent = cursor == null ? [] : state.navigations.slice(cursor)
    return {
      url: location.href,
      document: state.document,
      cursor: state.navigations.length,
      kind: recent.at(-1)?.kind ?? 'document'
    }
  }
  """

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

  @doc """
  Reads the frame's document identity, URL and LiveView navigations since `cursor`.

  `evaluate` has no timeout and waits while a script blocks the page's main
  thread, so the read gives up after `timeout`.
  """
  def probe!(frame, cursor, timeout), do: probe!(frame, cursor, timeout, Deadline.new(timeout))

  defp probe!(frame, cursor, timeout, deadline) do
    case Bounded.within(Deadline.remaining(deadline, 1), fn -> Frame.evaluate(frame, @probe, cursor) end) do
      {:ok, {:ok, %{"url" => url, "document" => document, "cursor" => next, "kind" => kind}}} ->
        %{url: url, document: document, cursor: next, kind: kind(kind)}

      # A navigation replaced the execution context mid-call; read the new one.
      # A redirect chain (a page that navigates on load) replaces several.
      {:ok, {:error, error}} ->
        if context_destroyed?(error) and not Deadline.expired?(deadline),
          do: probe!(frame, cursor, timeout, deadline),
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

  # The activation state lives in the document of the frame `locator` resolves
  # in, possibly a child frame. `evaluate_all` runs there without waiting for a
  # match, and has no timeout of its own.

  @doc "Marks the checkbox and radio activations `activated?/4` reads; `nil` if the frame cannot be read."
  def activation_cursor(locator, timeout) do
    expression = "() => { const state = #{@state}; return [state.document, state.activations.count] }"

    case Bounded.within(timeout, fn -> Locator.evaluate_all(locator, expression) end) do
      {:ok, {:ok, cursor}} -> cursor
      _unreadable -> nil
    end
  end

  @doc "Whether a checkbox or radio activation in the same document since `cursor` left it `checked`."
  def activated?(_locator, nil, _checked, _timeout), do: false

  def activated?(locator, [document, count], checked, timeout) do
    expression = """
    (_elements, [document, count, checked]) => window.__fluffy?.document === document &&
      window.__fluffy.activations.count > count && window.__fluffy.activations.checked === checked
    """

    read = Bounded.within(timeout, fn -> Locator.evaluate_all(locator, expression, [document, count, checked]) end)
    match?({:ok, {:ok, true}}, read)
  end

  def wait_for_live_view!(frame, destination, timeout) do
    case Frame.wait_for_function(frame, @live_view_ready, nil, timeout: timeout) do
      {:ok, handle} ->
        release(handle)

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
  defp release(handle) do
    {:ok, _pid} = Task.Supervisor.start_child(Fluffy.TaskSupervisor, fn -> JSHandle.dispose(handle) end)
    :ok
  end

  defp kind("patch"), do: :patch
  defp kind("redirect"), do: :redirect
  defp kind(_document), do: :document
end
