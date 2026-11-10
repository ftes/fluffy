defmodule Fluffy.Driver.Playwright do
  @moduledoc false

  @behaviour Fluffy.Driver.Contract

  alias Fluffy.Backend.Playwright.Document
  alias Fluffy.Backend.Playwright.Listeners
  alias Fluffy.Deadline
  alias Fluffy.Expect
  alias Fluffy.FileChooser
  alias Fluffy.Internal.Navigation
  alias Fluffy.Internal.OperationFailure
  alias Fluffy.Locator
  alias Fluffy.Locator.Playwright, as: PlaywrightLocator
  alias Fluffy.Session
  alias Fluffy.URLMatcher
  alias PlaywrightEx.AbortController
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Dialog
  alias PlaywrightEx.Expect, as: BrowserExpect
  alias PlaywrightEx.Frame
  alias PlaywrightEx.Locator, as: BrowserLocator
  alias PlaywrightEx.Page, as: BrowserPage
  alias PlaywrightEx.Promise
  alias PlaywrightEx.TargetClosedError
  alias PlaywrightEx.TimeoutError

  @impl true
  def open_browser(%Session{} = session, open_fun) do
    frame = Session.page_state(session).frame

    html =
      case Frame.content(frame) do
        {:ok, html} -> html
        {:error, error} -> OperationFailure.raise_playwright!(:open_browser, nil, error)
      end

    url = Session.current_page(session).url
    resolver = fn path -> URI.to_string(URI.merge(url, path)) end
    Fluffy.OpenBrowser.write(LazyHTML.from_document(html), resolver, open_fun)
    session
  end

  @impl true
  def validate_operation!(_session, _operation, _arguments), do: :ok

  @impl true
  def expect(%Session{} = session, %Expect{} = expectation) do
    action = fn ->
      execute_expectation(session, expectation)
      {:ok, :expectation}
    end

    case navigation_aware_action(session, action) do
      {:ok, :expectation, outcome} -> outcome
      {:error, error} -> expectation_failed!(expectation, error)
    end
  end

  defp execute_expectation(session, %Expect{target: :page, kind: :url, expected: expected} = expectation) do
    page = Session.page_state(session).page
    matcher = fn url -> URLMatcher.matches?(expected, url) != expectation.negated? end
    timeout = Session.timeout(session, expectation.options)

    case BrowserPage.wait_for_url(page, matcher, wait_until: :commit, timeout: timeout) do
      :ok ->
        :ok

      {:error, error} ->
        raise ExUnit.AssertionError,
          message:
            "Expected #{Expect.Internal.describe(expectation)}, got #{inspect(BrowserPage.url(page))}\n" <>
              Exception.message(error)
    end
  end

  defp execute_expectation(session, %Expect{} = expectation) do
    {target, assertion, arguments, options} = native_expectation(session, expectation)
    target = if expectation.negated?, do: BrowserExpect.not_(target), else: target

    options = Keyword.put(options, :timeout, Session.timeout(session, expectation.options))

    case apply(BrowserExpect, assertion, [target | arguments] ++ [options]) do
      :ok ->
        :ok

      {:error, error} ->
        expectation_failed!(expectation, error)
    end
  end

  defp expectation_failed!(expectation, error) do
    raise ExUnit.AssertionError,
      message: "Expected #{Expect.Internal.describe(expectation)}\n" <> Exception.message(error)
  end

  defp native_expectation(session, %Expect{target: :page, kind: :title, expected: expected}),
    do: {Session.page_state(session).page, :to_have_title, [expected], []}

  defp native_expectation(session, %Expect{target: :page, kind: :aria_snapshot, expected: expected}) do
    {assertion, arguments, options} = locator_assertion(:aria_snapshot, expected)
    {Session.page_state(session).page, assertion, arguments, options}
  end

  defp native_expectation(session, %Expect{target: target, kind: :screenshot, expected: options}) do
    native =
      case target do
        :page -> Session.page_state(session).page
        {:locator, locator} -> locator(session, locator)
      end

    options = resolve_mask(options, session)
    {native, :to_have_screenshot, [], options}
  end

  @state_assertions %{
    attached: :to_be_attached,
    disabled: :to_be_disabled,
    editable: :to_be_editable,
    empty: :to_be_empty,
    enabled: :to_be_enabled,
    focused: :to_be_focused,
    hidden: :to_be_hidden,
    visible: :to_be_visible
  }

  @value_assertions %{
    class: :to_have_class,
    contain_class: :to_contain_class,
    count: :to_have_count,
    id: :to_have_id,
    role: :to_have_role,
    value: :to_have_value,
    values: :to_have_values
  }

  defp native_expectation(session, %Expect{target: {:locator, locator}, kind: kind, expected: expected}) do
    {assertion, arguments, options} = locator_assertion(kind, expected)
    {locator(session, locator), assertion, arguments, options}
  end

  defp locator_assertion(:checked, :checked), do: {:to_be_checked, [], []}
  defp locator_assertion(:checked, :unchecked), do: {:to_be_checked, [], [checked: false]}
  defp locator_assertion(:checked, :indeterminate), do: {:to_be_checked, [], [indeterminate: true]}
  defp locator_assertion(:text, {expected, options}), do: {:to_have_text, [expected], options}
  defp locator_assertion(:contain_text, {expected, options}), do: {:to_contain_text, [expected], options}
  defp locator_assertion(:attribute, {name, value, options}), do: {:to_have_attribute, [name, value], options}
  defp locator_assertion(:in_viewport, options), do: {:to_be_in_viewport, [], options}
  defp locator_assertion(:aria_snapshot, {expected, options}), do: {:to_match_aria_snapshot, [expected], options}
  defp locator_assertion(:css, {name, value, options}), do: {:to_have_css, [name, value], options}
  defp locator_assertion(:js_property, {name, value}), do: {:to_have_js_property, [name, value], []}
  defp locator_assertion(:accessible_name, {expected, options}), do: {:to_have_accessible_name, [expected], options}

  defp locator_assertion(:accessible_description, {expected, options}),
    do: {:to_have_accessible_description, [expected], options}

  defp locator_assertion(:accessible_error_message, {expected, options}),
    do: {:to_have_accessible_error_message, [expected], options}

  defp locator_assertion(kind, _expected) when is_map_key(@state_assertions, kind),
    do: {Map.fetch!(@state_assertions, kind), [], []}

  defp locator_assertion(kind, expected) when is_map_key(@value_assertions, kind),
    do: {Map.fetch!(@value_assertions, kind), [expected], []}

  @impl true
  def set_html(%Session{} = session, html) when is_binary(html) do
    frame = Session.page_state(session).frame
    expression = "html => { document.querySelector('#fluffy-test-root').innerHTML = html }"
    with {:error, error} <- Frame.evaluate(frame, expression, html), do: raise(error)
    session
  end

  @impl true
  def click(%Session{} = session, %Locator{} = locator, options \\ []) do
    locator_action(session, :click, locator, options, &BrowserLocator.click(&1, native(options, &2)))
  end

  # Submits the form and reports whether it asks the page's main frame to
  # navigate: validation let the submit event fire, no handler (such as
  # LiveView's phx-submit) cancelled it, and its target is that frame. This
  # stands in for the browser's navigation request that a Playwright action
  # waits on, which WebKit sends only after requestSubmit has returned. Page
  # inputs can shadow form properties, so they are read from the prototype.
  @submit """
  form => {
    if (form.localName !== 'form')
      throw new Error(`submit/2 requires a form locator, got ${form.localName}`)
    const view = form.ownerDocument.defaultView
    const property = name => Object.getOwnPropertyDescriptor(HTMLFormElement.prototype, name).get.call(form)
    let submitted
    const listen = event => { if (event.target === form) submitted = event }
    view.addEventListener('submit', listen, true)
    try { HTMLFormElement.prototype.requestSubmit.call(form) } finally {
      view.removeEventListener('submit', listen, true)
    }

    if (!submitted || submitted.defaultPrevented || !form.isConnected || property('method') === 'dialog') return false
    if (!['http:', 'https:'].includes(new URL(property('action')).protocol)) return false
    const name = property('target') || form.ownerDocument.querySelector('base[target]')?.getAttribute('target') || '_self'
    const keyword = name.toLowerCase()
    const target = keyword === '_self' ? view : keyword === '_parent' ? view.parent : keyword === '_top' ? view.top
      : name === view.name ? view : null
    return target === view.top
  }
  """

  # Like a Playwright action, submit waits for the navigation it starts to
  # commit, navigate within the document or fail (a no-content or download
  # response aborts it), and no longer. Waiting before submitting misses no
  # commit. A `beforeunload` prompt also ends the wait: dismissing it cancels
  # the navigation before the browser requests it, so a click would not wait,
  # and its close does not say how it was handled.
  @impl true
  def submit(%Session{} = session, %Locator{} = locator, options \\ []) do
    %{page: page, frame: frame} = Session.page_state(session)

    locator_action(session, :submit, locator, options, fn native, remaining ->
      prompted = AbortController.new()

      navigation =
        Frame.wait_for_navigation(frame,
          wait_until: :commit,
          timeout: remaining,
          signal: AbortController.signal(prompted)
        )

      unload_prompted = fn dialog -> if Dialog.type(dialog) == "beforeunload", do: AbortController.abort(prompted) end
      listeners = Listeners.register([{BrowserPage, page, :dialog_closed, unload_prompted}])

      try do
        case BrowserLocator.evaluate(native, @submit, nil, timeout: remaining) do
          {:ok, true} -> await_navigation(navigation)
          {:ok, false} -> :ok
          {:error, error} -> {:error, error}
        end
      after
        Listeners.release(listeners)
        Promise.free(navigation)
      end
    end)
  end

  # Playwright's wait ends without error when the navigation fails or its page
  # closes; only a timeout fails the action.
  defp await_navigation(navigation) do
    case Promise.await(navigation) do
      {:error, %TimeoutError{} = error} -> {:error, error}
      _committed_failed_or_prompted -> :ok
    end
  end

  @impl true
  def fill(%Session{} = session, %Locator{} = locator, value, options \\ []) when is_binary(value) do
    locator_action(session, :fill, locator, options, &BrowserLocator.fill(&1, value, native(options, &2)))
  end

  @impl true
  def clear(%Session{} = session, %Locator{} = locator, options \\ []) do
    locator_action(session, :clear, locator, options, &BrowserLocator.clear(&1, native(options, &2)))
  end

  @impl true
  def set_input_files(%Session{} = session, %Locator{} = locator, source, _selected_files, options) do
    files = files(source)
    locator_action(session, :set_input_files, locator, options, &BrowserLocator.set_input_files(&1, files, timeout: &2))
  end

  def set_input_files(%Session{} = session, %FileChooser{} = chooser, source, _selected_files, options) do
    files = files(source)

    action(session, :set_input_files, chooser, options, fn remaining ->
      PlaywrightEx.FileChooser.set_files(chooser.native, files, timeout: remaining)
    end)
  end

  @impl true
  def set_checked(%Session{} = session, %Locator{} = locator, desired, options \\ []) when is_boolean(desired) do
    {operation, set} = if desired, do: {:check, &BrowserLocator.check/2}, else: {:uncheck, &BrowserLocator.uncheck/2}
    locator_action(session, operation, locator, options, &set.(&1, native(options, &2)))
  end

  @impl true
  def select_option(%Session{} = session, %Locator{} = locator, requested, options \\ []) do
    locator_action(
      session,
      :select_option,
      locator,
      options,
      &BrowserLocator.select_option(&1, requested, native(options, &2))
    )
  end

  def focus(%Session{} = session, %Locator{} = locator, options \\ []) do
    locator_action(session, :focus, locator, options, &BrowserLocator.focus(&1, timeout: &2))
  end

  def blur(%Session{} = session, %Locator{} = locator, options \\ []) do
    locator_action(session, :blur, locator, options, &BrowserLocator.blur(&1, timeout: &2))
  end

  @impl true
  def press(%Session{} = session, %Locator{} = locator, key, options \\ []) do
    locator_action(session, :press, locator, options, &BrowserLocator.press(&1, key, native(options, &2)))
  end

  def hover(session, locator, options) do
    locator_action(session, :hover, locator, options, &BrowserLocator.hover(&1, native(options, &2)))
  end

  def drag_to(session, source, target, options) do
    target = locator(session, target)

    locator_action(session, :drag_to, source, options, fn native_source, remaining ->
      BrowserLocator.drag_to(native_source, target, native(options, remaining))
    end)
  end

  def press_sequentially(session, locator, text, options) when is_binary(text) do
    locator_action(session, :press_sequentially, locator, options, fn native_locator, remaining ->
      BrowserLocator.press_sequentially(native_locator, text, native(options, remaining))
    end)
  end

  def dblclick(session, locator, options) do
    locator_action(session, :dblclick, locator, options, &BrowserLocator.dblclick(&1, native(options, &2)))
  end

  def tap(session, locator, options) do
    locator_action(session, :tap, locator, options, &BrowserLocator.tap(&1, native(options, &2)))
  end

  def dispatch_event(session, locator, type, event_init, options) do
    locator_action(session, :dispatch_event, locator, options, fn native_locator, remaining ->
      BrowserLocator.dispatch_event(native_locator, type, event_init, native(options, remaining))
    end)
  end

  def select_text(session, locator, options) do
    locator_action(session, :select_text, locator, options, &BrowserLocator.select_text(&1, native(options, &2)))
  end

  def scroll_into_view_if_needed(session, locator, options) do
    locator_action(session, :scroll_into_view_if_needed, locator, options, fn native_locator, remaining ->
      BrowserLocator.scroll_into_view_if_needed(native_locator, native(options, remaining))
    end)
  end

  def wait_for(session, locator, options) do
    locator_action(session, :wait_for, locator, options, &BrowserLocator.wait_for(&1, native(options, &2)))
  end

  def drop(session, locator, payload, options) do
    locator_action(session, :drop, locator, options, &BrowserLocator.drop(&1, payload, native(options, &2)))
  end

  def locator_wait_for_function(session, locator, expression, arg, options) do
    locator_action(
      session,
      :wait_for_function,
      locator,
      options,
      &BrowserLocator.wait_for_function(&1, expression, arg, native(options, &2))
    )
  end

  # As in Playwright, `timeout:` limits finding the element, not reading its box.
  def bounding_box(session, locator, options) do
    locator_read(session, :bounding_box, locator, options, &BrowserLocator.bounding_box(&1, native(options, &2)))
  end

  def aria_snapshot(session, locator, options) do
    native_locator = locator(session, locator)
    read(session, :aria_snapshot, locator, options, &BrowserLocator.aria_snapshot(native_locator, native(options, &1)))
  end

  def page_aria_snapshot(session, options) do
    page = Session.page_state(session).page
    read(session, :aria_snapshot, nil, options, &BrowserPage.aria_snapshot(page, native(options, &1)))
  end

  # As in Playwright, a page read has no timeout and waits while a script blocks the page.
  def page_read(session, operation, fun) do
    page = Session.page_state(session).page
    read(session, operation, nil, [], fn _remaining -> fun.(page) end)
  end

  # As in Playwright, `timeout:` limits finding the element, not the evaluation.
  def locator_evaluate(session, locator, expression, arg, options) do
    locator_read(session, :evaluate, locator, options, &BrowserLocator.evaluate(&1, expression, arg, native(options, &2)))
  end

  def evaluate_all(session, locator, expression, arg) do
    locator_read(session, :evaluate_all, locator, [], fn native_locator, _remaining ->
      BrowserLocator.evaluate_all(native_locator, expression, arg)
    end)
  end

  defp read(session, operation, target, options, fun) do
    timeout = Session.operation_timeout!(session, operation, options)

    case navigation_aware_action(session, fn -> fun.(timeout) end) do
      {:ok, value, outcome} -> {:return, value, outcome}
      {:error, error} -> OperationFailure.raise_playwright!(operation, target, error)
    end
  end

  def screenshot(session, locator, path, options) do
    options =
      options
      |> Keyword.put(:path, path)
      |> resolve_mask(session)

    locator_action(session, :screenshot, locator, options, &BrowserLocator.screenshot(&1, native(options, &2)))
  end

  # As in Playwright, page-wide input and emulation have no timeout and wait while
  # a script blocks the page. Unlike a locator action, Playwright does not wait for
  # a navigation the input starts, which may commit after this returns; the next
  # call adopts it then.
  def page_action(%Session{} = session, operation, fun) do
    page = Session.page_state(session).page
    action(session, operation, nil, [], fn _remaining -> fun.(page) end)
  end

  # `fun` gets the native options, with the timeout, and may return a handle.
  # Playwright's own timeout ends the wait, even while a script blocks the page.
  def page_wait(%Session{} = session, operation, fun, options) do
    page = Session.page_state(session).page

    action(session, operation, nil, options, fn remaining ->
      with {:ok, handle} <- fun.(page, native(options, remaining)), do: Document.release(handle)
    end)
  end

  defp resolve_mask(options, session),
    do: Keyword.replace_lazy(options, :mask, fn mask -> Enum.map(mask, &locator(session, &1)) end)

  defp locator_read(session, operation, locator, options, call) do
    native_locator = locator(session, locator)
    read(session, operation, locator, options, &call.(native_locator, &1))
  end

  @impl true
  def unwrap(%Session{} = session, fun) when is_function(fun, 1),
    do: session |> run_unwrapped(:unwrap, nil, Session.page_state(session).page, fun) |> discard_return()

  @impl true
  def unwrap_and_return(%Session{} = session, fun) when is_function(fun, 1),
    do: run_unwrapped(session, :unwrap_and_return, nil, Session.page_state(session).page, fun)

  # Like unwrap/2, with the locator resolved in the current frame.
  def unwrap_locator(%Session{} = session, %Locator{} = locator, fun) when is_function(fun, 1),
    do: session |> run_unwrapped(:unwrap, locator, locator(session, locator), fun) |> discard_return()

  def unwrap_and_return_locator(%Session{} = session, %Locator{} = locator, fun) when is_function(fun, 1),
    do: run_unwrapped(session, :unwrap_and_return, locator, locator(session, locator), fun)

  # The callback's own errors pass through; Fluffy's adoption before it raises
  # `Fluffy.OperationError`.
  defp run_unwrapped(session, operation, target, native, fun) do
    page = Session.page_state(session).page
    context = Session.context(session)

    action = fn ->
      result = fun.(native)
      validate_unwrapped!(context.browser_context, page)
      {:ok, result}
    end

    case navigation_aware_action(session, action) do
      {:ok, result, outcome} -> {:return, result, outcome}
      {:error, error} -> OperationFailure.raise_playwright!(operation, target, error)
    end
  end

  defp discard_return({:return, _ignored, outcome}), do: outcome

  # As in Playwright, a clock call has no timeout and waits while a timer it
  # fires blocks the page. Those timers can patch or navigate, as an action can.
  def clock(%Session{} = session, operation, fun) do
    clock = BrowserPage.clock(Session.page_state(session).page)

    case navigation_aware_action(session, fn -> result(fun.(clock)) end) do
      {:ok, :ok, outcome} -> outcome
      {:error, error} -> OperationFailure.raise_playwright!(operation, nil, error)
    end
  end

  defp validate_unwrapped!(browser_context, page) do
    cond do
      BrowserContext.is_closed(browser_context) -> invalidated!(:context)
      BrowserPage.is_closed(page) -> invalidated!(:page)
      true -> :ok
    end
  end

  defp invalidated!(kind) do
    raise ArgumentError,
          "Playwright unwrap invalidated the tracked #{kind}; use Fluffy page and session lifecycle APIs"
  end

  defp locator(session, locator), do: PlaywrightLocator.locator(Session.page_state(session).frame, locator)

  # Fluffy's own options stay here; the rest pass through to the PlaywrightEx call.
  defp native(options, remaining), do: Keyword.put(options, :timeout, remaining)

  defp locator_action(session, operation, locator, options, fun) do
    native = locator(session, locator)
    action(session, operation, locator, options, &fun.(native, &1))
  end

  defp action(session, operation, target, options, fun) do
    timeout = Session.operation_timeout!(session, operation, options)

    case navigation_aware_action(session, fn -> result(fun.(timeout)) end) do
      {:ok, _value, outcome} -> outcome
      {:error, error} -> OperationFailure.raise_playwright!(operation, target, error)
    end
  end

  defp result(:ok), do: {:ok, :ok}
  defp result(result), do: result

  # An action's own error is Playwright's; Firefox fails an action that closes its
  # own page, which Playwright leaves as a known Firefox bug.
  defp navigation_aware_action(session, action) do
    # Browser bookkeeping has its own budget; it must not consume a short
    # action/assertion timeout or silently leave navigation state stale.
    with {:ok, session, before} <- prepare_document(session) do
      state = Session.page_state(session)

      with {:ok, value} <- action.(),
           do: {:ok, value, reconcile_action_navigation(session, state, before, Document.bookkeeping_timeout(session))}
    end
  end

  # Adopts a document Fluffy has not seen: a new page's first document, or a
  # navigation that happened outside Fluffy (a late one, or through unwrap/2).
  defp prepare_document(session) do
    state = Session.page_state(session)
    timeout = Document.bookkeeping_timeout(session)
    probe = open_page_probe!(session, state, timeout)

    if probe.document == state.document_identity do
      {:ok, session, probe}
    else
      state = %{state | document_identity: probe.document}
      session = Fluffy.Backend.navigate(session, Navigation.browser_committed(probe.url, state))
      {:ok, session, open_page_probe!(session, state, timeout)}
    end
  rescue
    # The page closed while Fluffy adopted its document for this operation.
    error in TargetClosedError -> {:error, error}
  end

  # The runtime may not have processed a close yet; report it as it would.
  defp open_page_probe!(session, state, timeout) do
    Document.adopted_probe!(state, nil, timeout)
  rescue
    TargetClosedError -> raise ArgumentError, "page #{inspect(session.active_page)} is closed"
  end

  # Like Playwright, an operation that succeeded is not failed by a close after it.
  # Navigation bookkeeping ends with the page; its handle is closed.
  defp reconcile_action_navigation(session, state, before, bookkeeping_timeout) do
    if BrowserPage.is_closed(state.page),
      do: session,
      else: reconcile_open_page_navigation(session, state, before, Deadline.new(bookkeeping_timeout))
  rescue
    TargetClosedError -> session
  end

  defp reconcile_open_page_navigation(session, state, before, deadline) do
    probe = Document.adopted_probe!(state, before.cursor, Deadline.remaining(deadline, 1))

    probe =
      if probe.document == state.document_identity and probe.kind in [:redirect, :patch] do
        Document.wait_for_navigations!(state.frame, before.cursor, Deadline.remaining(deadline, 1))
        Document.probe!(state.frame, before.cursor, Deadline.remaining(deadline, 1))
      else
        probe
      end

    navigation =
      cond do
        probe.document != state.document_identity ->
          Navigation.browser_committed(probe.url, %{state | document_identity: probe.document})

        probe.kind == :redirect ->
          Navigation.browser_committed(probe.url, state, live_navigation_cursor: before.cursor)

        probe.url != before.url ->
          Navigation.browser_patch(probe.url, state)

        true ->
          nil
      end

    if navigation, do: Fluffy.Backend.navigate(session, navigation), else: session
  end

  defp files({:local_paths, paths}), do: paths

  defp files({:payloads, payloads}) do
    Enum.map(payloads, &%{name: &1.name, mimeType: &1.content_type, buffer: &1.bytes})
  end
end
