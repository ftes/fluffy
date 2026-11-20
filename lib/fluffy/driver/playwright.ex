defmodule Fluffy.Driver.Playwright do
  @moduledoc false

  @behaviour Fluffy.Driver.Contract

  alias Fluffy.Deadline
  alias Fluffy.Driver.Playwright.Document
  alias Fluffy.Driver.Playwright.Listeners
  alias Fluffy.Driver.Playwright.Locator, as: PlaywrightLocator
  alias Fluffy.Expect
  alias Fluffy.FileChooser
  alias Fluffy.Internal.NavigationFailure
  alias Fluffy.Internal.OperationFailure
  alias Fluffy.Locator
  alias Fluffy.Session
  alias Fluffy.Timeouts
  alias Playwright.AbortController
  alias Playwright.BrowserContext
  alias Playwright.Client.Errors
  alias Playwright.Dialog
  alias Playwright.Expect, as: BrowserExpect
  alias Playwright.ExpectError
  alias Playwright.Frame
  alias Playwright.Locator, as: BrowserLocator
  alias Playwright.Page, as: BrowserPage
  alias Playwright.Promise
  alias Playwright.TargetClosedError
  alias Playwright.TimeoutError

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

    case navigation_aware_action(session, :expect, Timeouts.get(expectation.options, &Timeouts.expect/0), action) do
      {:ok, :expectation, outcome} -> outcome
      {:error, error} -> expectation_failed!(expectation, error, "")
    end
  end

  defp execute_expectation(session, %Expect{} = expectation) do
    {target, assertion, arguments, options} = native_expectation(session, expectation)
    target = if expectation.negated?, do: BrowserExpect.not_(target), else: target

    options = Keyword.put(options, :timeout, expect_timeout(expectation))

    case apply(BrowserExpect, assertion, [target | arguments] ++ [options]) do
      :ok ->
        :ok

      {:error, error} ->
        expectation_failed!(expectation, error, "")
    end
  end

  # Upstream's expectScreenshot takes each screenshot under the expect timeout, so a
  # screenshot assertion can't check once at 1ms, as an action can't.
  defp expect_timeout(%Expect{kind: :screenshot, options: options}),
    do: Deadline.playwright_operation!(:to_have_screenshot, Timeouts.get(options, &Timeouts.expect/0))

  defp expect_timeout(expectation), do: Timeouts.playwright_expect(expectation.options)

  # As in Playwright, where the client's `_expect` turns every `PlaywrightError`
  # (timeouts, closed targets and aborts included) into a failed matcher, any
  # Playwright error fails the expectation, a close while Fluffy adopts the page
  # too. Other errors, such as a bad argument, pass through.
  @spec expectation_failed!(Expect.t(), Exception.t(), String.t()) :: no_return()
  defp expectation_failed!(expectation, error, received) do
    if is_struct(error, ExpectError) or Errors.is_playwright_error(error) do
      raise ExUnit.AssertionError,
        message: "Expected #{Expect.Internal.describe(expectation)}#{received}\n" <> Exception.message(error)
    else
      raise error
    end
  end

  defp native_expectation(session, %Expect{target: :page, kind: :title, expected: expected}),
    do: {Session.page_state(session).page, :to_have_title, [expected], []}

  defp native_expectation(session, %Expect{target: :page, kind: :url, expected: {expected, options}}),
    do: {Session.page_state(session).page, :to_have_url, [expected], options}

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
      throw new Error(`Fluffy.submit/3: requires a form locator, got ${form.localName}`)
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
      Playwright.FileChooser.set_files(chooser.native, files, timeout: remaining)
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

  @impl true
  def press(%Session{} = session, %Locator{} = locator, key, options \\ []) do
    locator_action(session, :press, locator, options, &BrowserLocator.press(&1, key, native(options, &2)))
  end

  @impl true
  def text_content(%Session{} = session, %Locator{} = locator, options \\ []),
    do: locator_read(session, :text_content, locator, options, &BrowserLocator.text_content(&1, native(options, &2)))

  # As in Playwright, these list reads don't wait and have no timeout.
  @impl true
  def all_text_contents(%Session{} = session, %Locator{} = locator, _options \\ []),
    do:
      locator_read(session, :all_text_contents, locator, [], fn native, _remaining ->
        BrowserLocator.all_text_contents(native)
      end)

  def all_inner_texts(%Session{} = session, %Locator{} = locator),
    do:
      locator_read(session, :all_inner_texts, locator, [], fn native, _remaining ->
        BrowserLocator.all_inner_texts(native)
      end)

  @impl true
  def get_attribute(%Session{} = session, %Locator{} = locator, name, options \\ []) do
    locator_read(session, :get_attribute, locator, options, &BrowserLocator.get_attribute(&1, name, native(options, &2)))
  end

  @impl true
  def input_value(%Session{} = session, %Locator{} = locator, options \\ []),
    do: locator_read(session, :input_value, locator, options, &BrowserLocator.input_value(&1, native(options, &2)))

  defp locator_read(session, operation, locator, options, fun) do
    native = locator(session, locator)
    read(session, operation, locator, options, &fun.(native, &1))
  end

  # The driver's end of `Fluffy.Playwright.__call__/7`, which documents the contract. As in
  # Playwright, a locator's `timeout:` limits finding its element, not a read of it.
  def native_call(session, kind, {operation, native}, target, arguments, options) do
    {module, function, _arity} = Keyword.fetch!(Fluffy.Options.playwright_actions(), native)
    options = resolve_mask(options, session)
    arguments = native_arguments(session, native, arguments)

    {native_target, target} =
      if target == :page, do: {Session.page_state(session).page, nil}, else: {locator(session, target), target}

    call = &apply(module, function, [native_target | arguments] ++ [native(options, &1)])

    case kind do
      :action ->
        action(session, operation, target, options, call)

      :read ->
        read(session, operation, target, options, call)

      :wait ->
        action(session, operation, target, options, &with({:ok, handle} <- call.(&1), do: Document.release(handle)))
    end
  end

  # Only `drag_to`'s target is a locator to resolve; any other argument is data, such as a
  # `Fluffy.Locator` passed as the `arg` of an evaluation.
  defp native_arguments(session, :drag_to, [%Locator{} = target]), do: [locator(session, target)]
  defp native_arguments(_session, _native, arguments), do: arguments

  def evaluate_all(session, locator, expression, arg) do
    native_locator = locator(session, locator)

    read(session, :evaluate_all, locator, [], fn _remaining ->
      BrowserLocator.evaluate_all(native_locator, expression, arg)
    end)
  end

  # As in Playwright, a page read has no timeout and waits while a script blocks the page.
  def page_read(session, operation, fun) do
    page = Session.page_state(session).page
    read(session, operation, nil, [], fn _remaining -> fun.(page) end)
  end

  defp read(session, operation, target, options, fun) do
    default = Timeouts.operation(session, operation, options)
    timeout = Deadline.playwright_operation!(operation, default)

    case navigation_aware_action(session, operation, default, fn -> fun.(timeout) end) do
      {:ok, value, outcome} -> {:return, value, outcome}
      {:error, error} -> OperationFailure.raise_playwright!(operation, target, error)
    end
  end

  # As in Playwright, page-wide input and emulation have no timeout and wait while
  # a script blocks the page. Unlike a locator action, Playwright does not wait for
  # a navigation the input starts, which may commit after this returns; the next
  # call adopts it then.
  def page_action(%Session{} = session, operation, fun) do
    page = Session.page_state(session).page
    action(session, operation, nil, [], fn _remaining -> fun.(page) end)
  end

  defp resolve_mask(options, session),
    do: Keyword.replace_lazy(options, :mask, fn mask -> Enum.map(mask, &locator(session, &1)) end)

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

  # The callback's own errors pass through, also one it returns for a call that
  # the close of its page or context ended; Fluffy's adoption before it raises
  # `Fluffy.OperationError`.
  defp run_unwrapped(session, operation, target, native, fun) do
    page = Session.page_state(session).page
    context = Session.context(session)

    action = fn ->
      result = fun.(native)
      validate_unwrapped!(context.browser_context, page, result)
      {:ok, result}
    end

    case navigation_aware_action(session, operation, Timeouts.action(session), action) do
      {:ok, result, outcome} -> {:return, result, outcome}
      {:error, error} -> OperationFailure.raise_playwright!(operation, target, error)
    end
  end

  defp discard_return({:return, _ignored, outcome}), do: outcome

  # As in Playwright, a clock call has no timeout and waits while a timer it
  # fires blocks the page. Those timers can patch or navigate, as an action can.
  def clock(%Session{} = session, operation, fun) do
    clock = BrowserPage.clock(Session.page_state(session).page)

    case navigation_aware_action(session, operation, Timeouts.action(session), fn -> result(fun.(clock)) end) do
      {:ok, :ok, outcome} -> outcome
      {:error, error} -> OperationFailure.raise_playwright!(operation, nil, error)
    end
  end

  # A call the close ended, such as Playwright.Test's at the test timeout, fails
  # with Playwright's error and its call log.
  defp validate_unwrapped!(browser_context, page, result) do
    closed =
      cond do
        BrowserContext.is_closed(browser_context) -> :context
        BrowserPage.is_closed(page) -> :page
        true -> nil
      end

    with {:error, %TargetClosedError{} = error} when closed != nil <- result, do: raise(error)

    if closed, do: invalidated!(closed), else: :ok
  end

  defp invalidated!(kind) do
    raise ArgumentError,
          "Playwright unwrap invalidated the tracked #{kind}; use Fluffy page and session lifecycle APIs"
  end

  defp locator(session, locator), do: PlaywrightLocator.locator(Session.page_state(session).frame, locator)

  # Fluffy's own options stay here; the rest pass through to the Playwright call.
  defp native(options, remaining), do: Keyword.put(options, :timeout, remaining)

  defp locator_action(session, operation, locator, options, fun) do
    native = locator(session, locator)
    action(session, operation, locator, options, &fun.(native, &1))
  end

  defp action(session, operation, target, options, fun) do
    default = Timeouts.operation(session, operation, options)
    timeout = Deadline.playwright_operation!(operation, default)

    case navigation_aware_action(session, operation, default, fn -> result(fun.(timeout)) end) do
      {:ok, _value, outcome} -> outcome
      {:error, error} -> OperationFailure.raise_playwright!(operation, target, error)
    end
  end

  defp result(:ok), do: {:ok, :ok}
  defp result(result), do: result

  # An action's own error is Playwright's; Firefox fails an action that closes its
  # own page, which Playwright leaves as a known Firefox bug.
  # `timeout` is the operation's own (its `timeout:` or default). Browser
  # bookkeeping gets a budget of its own from it; it must not consume a short
  # action/assertion timeout or silently leave navigation state stale.
  # A navigation Fluffy found failed, before or after the action, is raised under
  # `operation`, the public name its caller holds.
  defp navigation_aware_action(session, operation, timeout, action) do
    bookkeeping_timeout = Document.bookkeeping_timeout(timeout)

    with {:ok, session, before} <- prepare_document(session, bookkeeping_timeout) do
      state = Session.page_state(session)

      with {:ok, value} <- action.(),
           do: {:ok, value, reconcile_action_navigation(session, state, before, bookkeeping_timeout)}
    end
  rescue
    failure in NavigationFailure -> reraise OperationFailure.navigation(session, operation, failure), __STACKTRACE__
  end

  # Adopts a document Fluffy has not seen: a new page's first document, or a
  # navigation that happened outside Fluffy (a late one, or through unwrap/2).
  defp prepare_document(session, timeout) do
    state = Session.page_state(session)
    probe = open_page_probe!(session, state, timeout)

    if probe.document == state.document_identity do
      {:ok, session, probe}
    else
      state = %{state | document_identity: probe.document}
      session = adopt_document(session, state, probe.url)
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

    cond do
      probe.document != state.document_identity -> adopt_probed_document(session, state, probe)
      probe.kind == :redirect -> adopt_document(session, state, probe.url, before.cursor)
      probe.url != before.url -> Session.commit_page(session, :playwright, state, probe.url, same_document: true)
      true -> session
    end
  end

  @doc """
  Adopts the document the main frame navigated to, as after `visit` or `reload`, and
  commits it. Its reads and LiveView waits get the navigation timeout, not a `timeout:`
  of the call, which bounds the navigation only.
  """
  def adopt_navigated_document(session, state) do
    timeout = Document.bookkeeping_timeout(Timeouts.navigation(session))
    adopt_probed_document(session, state, Document.adopted_probe!(state, nil, timeout))
  end

  @doc "Adopts the document a probe of the main frame found."
  def adopt_probed_document(session, state, probe),
    do: adopt_document(session, %{state | document_identity: probe.document}, probe.url)

  # Commits a document the browser navigated to once its LiveViews are connected, also
  # after the LiveView redirect recorded since `cursor`, which keeps the HTML document.
  # The LiveView waits of a navigation an action or page code started share the
  # navigation timeout, so with none they wait as `goto` does.
  defp adopt_document(session, state, url, cursor \\ nil) do
    deadline = Deadline.new(Document.bookkeeping_timeout(Timeouts.navigation(session)))
    if cursor, do: Document.wait_for_redirect!(state.frame, url, cursor, Deadline.remaining(deadline, 1))
    :ok = Document.wait_for_live_view!(state.frame, url, Deadline.remaining(deadline, 1))
    Session.commit_page(session, :playwright, state, url, live_redirect: cursor != nil)
  end

  defp files({:local_paths, paths}), do: paths

  defp files({:payloads, payloads}) do
    Enum.map(payloads, &%{name: &1.name, mimeType: &1.content_type, buffer: &1.bytes})
  end
end
