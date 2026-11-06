defmodule Fluffy.Driver.Playwright do
  @moduledoc false

  @behaviour Fluffy.Driver.Contract

  alias Fluffy.Backend.Playwright.Bounded
  alias Fluffy.Backend.Playwright.Document
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
  alias PlaywrightEx.Expect, as: BrowserExpect
  alias PlaywrightEx.Frame
  alias PlaywrightEx.Locator, as: BrowserLocator
  alias PlaywrightEx.Page, as: BrowserPage
  alias PlaywrightEx.Promise
  alias PlaywrightEx.Request
  alias PlaywrightEx.TargetClosedError
  alias PlaywrightEx.TimeoutError

  @impl true
  def open_browser(%Session{} = session, open_fun) do
    frame = Session.page_state(session).frame
    html = Bounded.within!(session_timeout(session), :content, fn -> Frame.content(frame) end)
    url = Session.current_page(session).url
    resolver = fn path -> URI.to_string(URI.merge(url, path)) end
    Fluffy.OpenBrowser.write(LazyHTML.from_document(html), resolver, open_fun)
    session
  end

  @impl true
  def validate_operation!(_session, _operation, _arguments), do: :ok

  @impl true
  def expect(%Session{} = session, %Expect{} = expectation) do
    timeout = Keyword.get(expectation.options, :timeout, Session.context(session).timeout)

    {:ok, :expectation, outcome} =
      navigation_aware_action(session, timeout, fn remaining ->
        execute_expectation(session, Expect.merge_options(expectation, timeout: remaining))
        {:ok, :expectation}
      end)

    outcome
  end

  defp execute_expectation(session, %Expect{target: :page, kind: :url, expected: expected} = expectation) do
    page = Session.page_state(session).page
    matcher = fn url -> URLMatcher.matches?(expected, url) != expectation.negated? end

    case BrowserPage.wait_for_url(page, matcher, wait_until: :commit, timeout: expect_timeout(session, expectation)) do
      :ok ->
        :ok

      {:error, error} ->
        raise ExUnit.AssertionError,
          message:
            "Expected #{Expect.describe(expectation)}, got #{inspect(BrowserPage.url(page))}\n" <>
              Exception.message(error)
    end
  end

  defp execute_expectation(session, %Expect{} = expectation) do
    {target, assertion, arguments, options} = native_expectation(session, expectation)
    target = if expectation.negated?, do: BrowserExpect.not_(target), else: target

    options = Keyword.put(options, :timeout, expect_timeout(session, expectation))

    case apply(BrowserExpect, assertion, [target | arguments] ++ [options]) do
      :ok ->
        :ok

      {:error, error} ->
        raise ExUnit.AssertionError, message: "Expected #{Expect.describe(expectation)}\n" <> Exception.message(error)
    end
  end

  defp native_expectation(session, %Expect{target: :page, kind: :title, expected: expected}),
    do: {Session.page_state(session).page, :to_have_title, [expected], []}

  defp native_expectation(session, %Expect{target: {:locator, locator}, kind: kind, expected: expected}) do
    locator = locator(session, locator)

    case kind do
      :count -> {locator, :to_have_count, [expected], []}
      :visible -> {locator, :to_be_visible, [], []}
      :disabled -> {locator, :to_be_disabled, [], []}
      :editable -> {locator, :to_be_editable, [], []}
      :enabled -> {locator, :to_be_enabled, [], []}
      :focused -> {locator, :to_be_focused, [], []}
      :value -> {locator, :to_have_value, [expected], []}
      :values -> {locator, :to_have_values, [expected], []}
      :checked when expected == :checked -> {locator, :to_be_checked, [], []}
      :checked when expected == :unchecked -> {locator, :to_be_checked, [], [checked: false]}
      :checked when expected == :indeterminate -> {locator, :to_be_checked, [], [indeterminate: true]}
    end
  end

  defp expect_timeout(session, expectation),
    do: expectation.options |> Keyword.get(:timeout, Session.context(session).timeout) |> max(1)

  @impl true
  def set_html(%Session{} = session, html) when is_binary(html) do
    frame = Session.page_state(session).frame
    expression = "html => { document.querySelector('#fluffy-test-root').innerHTML = html }"
    Bounded.within!(session_timeout(session), :set_html, fn -> Frame.evaluate(frame, expression, html) end)
    session
  end

  @impl true
  def click(%Session{} = session, %Locator{} = locator, options \\ []) do
    locator_action(session, :click, locator, options, &BrowserLocator.click(&1, native(options, &2)))
  end

  # Submits the form and reports whether it navigates the page's main frame:
  # validation let the submit event fire, no handler (such as LiveView's
  # phx-submit) cancelled it, and its target is that frame. Page inputs can
  # shadow form properties, so they are read from the prototype.
  @submit """
  form => {
    if (form.localName !== 'form')
      throw new Error(`submit/2 requires a form locator, got ${form.localName}`)
    const view = form.ownerDocument.defaultView
    const property = name => Object.getOwnPropertyDescriptor(HTMLFormElement.prototype, name).get.call(form)
    let submitted
    const listen = event => { if (event.target === form) submitted = event }
    view.addEventListener('submit', listen, true)
    try { HTMLFormElement.prototype.requestSubmit.call(form) } finally { view.removeEventListener('submit', listen, true) }

    if (!submitted || submitted.defaultPrevented || !form.isConnected || property('method') === 'dialog') return false
    if (!['http:', 'https:'].includes(new URL(property('action')).protocol)) return false
    const name = property('target') || form.ownerDocument.querySelector('base[target]')?.getAttribute('target') || '_self'
    const keyword = name.toLowerCase()
    const target = keyword === '_self' ? view : keyword === '_parent' ? view.parent : keyword === '_top' ? view.top
      : name === view.name ? view : null
    return target === view.top
  }
  """

  # Like a Playwright action, submit waits for a navigation it initiates;
  # WebKit can start it after requestSubmit has returned. The wait ends with the
  # response, when the server has handled the request, not the commit, which a
  # no-content or download response never makes.
  @impl true
  def submit(%Session{} = session, %Locator{} = locator, options \\ []) do
    %{page: page, frame: frame} = Session.page_state(session)

    locator_action(session, :submit, locator, options, fn native, remaining ->
      deadline = Deadline.new(remaining)
      # Listening first misses no request the submit starts.
      controller = AbortController.new()
      predicate = &(Request.is_navigation_request(&1) and Request.frame(&1).guid == frame.guid)
      signal = AbortController.signal(controller)
      navigation = BrowserPage.wait_for_event(page, :request, predicate: predicate, timeout: remaining, signal: signal)

      try do
        case BrowserLocator.evaluate(native, @submit, nil, timeout: remaining) do
          {:ok, true} -> with {:ok, request} <- Promise.await(navigation), do: await_response(request, deadline)
          {:ok, false} -> :ok
          {:error, error} -> {:error, error}
        end
      after
        AbortController.abort(controller)
        Promise.free(navigation)
      end
    end)
  end

  # A response has no timeout of its own; a failed request has none.
  defp await_response(request, deadline) do
    timeout = Deadline.remaining(deadline, 1)

    case Bounded.within(timeout, fn -> Request.response(request) end) do
      {:ok, {:ok, _response}} ->
        :ok

      {:ok, {:error, error}} ->
        {:error, error}

      :timeout ->
        {:error, %TimeoutError{message: "Timeout #{timeout}ms exceeded while waiting for the form submission response"}}
    end
  end

  @impl true
  def fill(%Session{} = session, %Locator{} = locator, value, options \\ []) when is_binary(value) do
    locator_action(session, :fill, locator, options, &BrowserLocator.fill(&1, value, native(options, &2)))
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
    frame = Session.page_state(session).frame

    locator_action(session, operation, locator, options, fn native, remaining ->
      cursor = Document.activation_cursor(frame, session_timeout(session))

      case set.(native, native(options, remaining)) do
        # Playwright reads the state after its click, which a LiveView patch
        # may already have changed (in Firefox and WebKit it usually has). As on
        # Phoenix, the action succeeds once the click set the requested state.
        {:error, %{message: message}} = error ->
          if message =~ "Clicking the checkbox did not change its state" and
               Document.activated?(frame, cursor, desired, session_timeout(session)),
             do: :ok,
             else: error

        result ->
          result
      end
    end)
  end

  @impl true
  def select_option(%Session{} = session, %Locator{} = locator, requested, options \\ []) do
    locator_action(session, :select_option, locator, options, fn native, remaining ->
      with {:ok, values} <- uniform_option_values(native, requested, remaining) do
        BrowserLocator.select_option(native, values, native(options, remaining))
      end
    end)
  end

  # Playwright takes either strings (matching value or label) or option maps.
  # A mixed list resolves its strings to option indexes.
  defp uniform_option_values(native, values, timeout) do
    if Enum.all?(values, &is_binary/1) or not Enum.any?(values, &is_binary/1) do
      {:ok, values}
    else
      expression = """
      (select, wanted) => wanted.map(value => {
        if (typeof value !== 'string') return value
        const index = [...select.options].findIndex(option => option.value === value || option.label === value)
        if (index < 0) throw new Error(`no option with value or label ${JSON.stringify(value)}`)
        return {index}
      })
      """

      with {:ok, resolved} <- BrowserLocator.evaluate(native, expression, values, timeout: timeout) do
        {:ok, Enum.map(resolved, &Map.new(&1, fn {key, value} -> {String.to_existing_atom(key), value} end))}
      end
    end
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

  @impl true
  def unwrap(%Session{} = session, fun) when is_function(fun, 1) do
    page = Session.page_state(session).page
    context = Session.context(session)

    {:ok, :unwrap, outcome} =
      navigation_aware_action(session, context.timeout, fn _remaining ->
        _ignored = fun.(page)
        validate_unwrapped!(context.browser_context, page)
        {:ok, :unwrap}
      end)

    outcome
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

  defp session_timeout(session), do: max(Session.context(session).timeout, 1)

  defp locator(session, locator), do: PlaywrightLocator.locator(Session.page_state(session).frame, locator)

  # Fluffy's own options stay here; the rest pass through to the PlaywrightEx call.
  defp native(options, remaining), do: options |> Keyword.drop([:timeout, :max_bytes]) |> Keyword.put(:timeout, remaining)

  defp locator_action(session, operation, locator, options, fun) do
    native = locator(session, locator)
    action(session, operation, locator, options, &fun.(native, &1))
  end

  defp action(session, operation, target, options, fun) do
    timeout = options |> Keyword.get(:timeout) |> Kernel.||(Session.context(session).timeout) |> max(1)

    case navigation_aware_action(session, timeout, &result(fun.(&1))) do
      {:ok, _value, outcome} -> outcome
      {:error, error} -> OperationFailure.raise_playwright!(operation, target, error)
    end
  end

  defp result(:ok), do: {:ok, :ok}
  defp result(result), do: result

  defp navigation_aware_action(session, operation_timeout, action) do
    # Browser bookkeeping has its own budget; it must not consume a short
    # action/assertion timeout or silently leave navigation state stale.
    {session, before} = prepare_document(session)
    state = Session.page_state(session)
    browser_context = Session.context(session).browser_context

    case action.(operation_timeout) do
      {:ok, value} ->
        deadline = Deadline.new(session_timeout(session))
        {:ok, value, reconcile_action_navigation(session, state, before, deadline)}

      # Playwright intends an action that closes its own page to succeed, but
      # Firefox can fail it. The page was open before the action.
      {:error, %TargetClosedError{} = error} ->
        if closed_own_page?(browser_context, state.page), do: {:ok, nil, session}, else: {:error, error}

      {:error, error} ->
        {:error, error}
    end
  end

  # A lost driver or a closed context closes the page too. The context's
  # closed flag may still lag a lost driver, unlike a call on it.
  defp closed_own_page?(browser_context, page) do
    BrowserPage.is_closed(page) and not BrowserContext.is_closed(browser_context) and
      match?({:ok, _cookies}, BrowserContext.cookies(browser_context, []))
  end

  # Adopts a document Fluffy has not seen: a new page's first document, or a
  # navigation that happened outside Fluffy (a late one, or through unwrap/2).
  defp prepare_document(session) do
    state = Session.page_state(session)
    timeout = session_timeout(session)
    probe = open_page_probe!(session, state, timeout)

    if probe.document == state.document_identity do
      {session, probe}
    else
      state = %{state | document_identity: probe.document}
      session = Fluffy.Backend.navigate(session, Navigation.browser_committed(probe.url, state))
      {session, open_page_probe!(session, state, timeout)}
    end
  end

  # The runtime may not have processed a close yet; report it as it would.
  defp open_page_probe!(session, state, timeout) do
    Document.probe!(state.frame, nil, timeout)
  rescue
    TargetClosedError -> raise ArgumentError, "page #{inspect(session.active_page)} is closed"
  end

  # Like Playwright, an action that closes its own page succeeds. Navigation
  # bookkeeping ends with the page; its handle is closed.
  defp reconcile_action_navigation(session, state, before, deadline) do
    if BrowserPage.is_closed(state.page),
      do: session,
      else: reconcile_open_page_navigation(session, state, before, deadline)
  rescue
    TargetClosedError -> session
  end

  defp reconcile_open_page_navigation(session, state, before, deadline) do
    probe = Document.probe!(state.frame, before.cursor, Deadline.remaining(deadline, 1))

    probe =
      if probe.document == state.document_identity and probe.kind in [:redirect, :patch] do
        Document.wait_for_navigations!(state.frame, before.cursor, Deadline.remaining(deadline, 1))
        Document.probe!(state.frame, before.cursor, Deadline.remaining(deadline, 1))
      else
        probe
      end

    cond do
      probe.document != state.document_identity ->
        state = %{state | document_identity: probe.document}
        {:navigate, session, Navigation.browser_committed(probe.url, state)}

      probe.kind == :redirect ->
        {:navigate, session, Navigation.browser_committed(probe.url, state, live_navigation_cursor: before.cursor)}

      probe.url != before.url ->
        {:navigate, session, Navigation.browser_patch(probe.url, state)}

      true ->
        session
    end
  end

  defp files({:local_paths, paths}), do: paths

  defp files({:payloads, payloads}) do
    Enum.map(payloads, &%{name: &1.name, mimeType: &1.content_type, buffer: &1.bytes})
  end
end
