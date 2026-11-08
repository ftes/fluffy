defmodule Fluffy.Driver.Playwright do
  @moduledoc false

  @behaviour Fluffy.Driver.Contract

  alias Fluffy.Backend.Playwright.Bounded
  alias Fluffy.Backend.Playwright.Document
  alias Fluffy.Backend.Playwright.Events
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
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Expect, as: BrowserExpect
  alias PlaywrightEx.Frame
  alias PlaywrightEx.Locator, as: BrowserLocator
  alias PlaywrightEx.Page, as: BrowserPage
  alias PlaywrightEx.PlaywrightError
  alias PlaywrightEx.Request
  alias PlaywrightEx.Response
  alias PlaywrightEx.TargetClosedError
  alias PlaywrightEx.TimeoutError

  @impl true
  def open_browser(%Session{} = session, open_fun) do
    frame = Session.page_state(session).frame
    html = Bounded.within!(Session.timeout(session), :content, fn -> Frame.content(frame) end)
    url = Session.current_page(session).url
    resolver = fn path -> URI.to_string(URI.merge(url, path)) end
    Fluffy.OpenBrowser.write(LazyHTML.from_document(html), resolver, open_fun)
    session
  end

  @impl true
  def validate_operation!(_session, _operation, _arguments), do: :ok

  @impl true
  def expect(%Session{} = session, %Expect{} = expectation) do
    timeout = Session.timeout(session, expectation.options)

    {:ok, :expectation, outcome} =
      navigation_aware_action(session, timeout, fn remaining ->
        execute_expectation(session, Expect.Internal.merge_options(expectation, timeout: remaining))
        {:ok, :expectation}
      end)

    outcome
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
        raise ExUnit.AssertionError,
          message: "Expected #{Expect.Internal.describe(expectation)}\n" <> Exception.message(error)
    end
  end

  defp native_expectation(session, %Expect{target: :page, kind: :title, expected: expected}),
    do: {Session.page_state(session).page, :to_have_title, [expected], []}

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

  defp locator_assertion(kind, _expected) when is_map_key(@state_assertions, kind),
    do: {Map.fetch!(@state_assertions, kind), [], []}

  defp locator_assertion(kind, expected) when is_map_key(@value_assertions, kind),
    do: {Map.fetch!(@value_assertions, kind), [expected], []}

  @impl true
  def set_html(%Session{} = session, html) when is_binary(html) do
    frame = Session.page_state(session).frame
    expression = "html => { document.querySelector('#fluffy-test-root').innerHTML = html }"
    Bounded.within!(Session.timeout(session), :set_html, fn -> Frame.evaluate(frame, expression, html) end)
    session
  end

  @impl true
  def click(%Session{} = session, %Locator{} = locator, options \\ []) do
    locator_action(session, :click, locator, options, &BrowserLocator.click(&1, native(options, &2)))
  end

  # Submits the form and reports whether it navigates the page's main frame to
  # another document: validation let the submit event fire, no handler (such as
  # LiveView's phx-submit) cancelled it, its target is that frame, and it is not
  # a GET to the current URL with a fragment, which the browser navigates to
  # within the document. Page inputs can shadow form properties, so they are
  # read from the prototype.
  @submit """
  form => {
    if (form.localName !== 'form')
      throw new Error(`submit/2 requires a form locator, got ${form.localName}`)
    const view = form.ownerDocument.defaultView
    const property = name => Object.getOwnPropertyDescriptor(HTMLFormElement.prototype, name).get.call(form)
    let submitted, data
    const listen = event => {
      if (event.target !== form) return
      if (event.type === 'submit') submitted = event
      else data = event.formData
    }
    view.addEventListener('submit', listen, true)
    view.addEventListener('formdata', listen, true)
    try { HTMLFormElement.prototype.requestSubmit.call(form) } finally {
      view.removeEventListener('submit', listen, true)
      view.removeEventListener('formdata', listen, true)
    }

    const method = property('method')
    if (!submitted || submitted.defaultPrevented || !form.isConnected || method === 'dialog') return false
    const url = new URL(property('action'))
    if (!['http:', 'https:'].includes(url.protocol)) return false
    const name = property('target') || form.ownerDocument.querySelector('base[target]')?.getAttribute('target') || '_self'
    const keyword = name.toLowerCase()
    const target = keyword === '_self' ? view : keyword === '_parent' ? view.parent : keyword === '_top' ? view.top
      : name === view.name ? view : null
    if (target !== view.top) return false
    if (method !== 'get' || !data) return true

    // A GET replaces the action's query with the form data, keeping its fragment.
    const entries = [...data].map(([key, value]) => [key, typeof value === 'string' ? value : value.name])
    url.search = '?' + new URLSearchParams(entries)
    let current
    try { current = target.location.href } catch { return true }
    const withoutFragment = href => href.split('#')[0]
    return !(url.href.includes('#') && withoutFragment(url.href) === withoutFragment(current))
  }
  """

  # Like a Playwright action, submit waits for a navigation it initiates;
  # WebKit can start it after requestSubmit has returned. The wait ends with the
  # final response of its redirect chain, when the server has handled the
  # request, not the commit, which a no-content or download response never
  # makes. Page code can still turn the navigation into a same-document one (the
  # Navigation API's `intercept()`), which ends the wait too. So does a
  # `beforeunload` dialog: dismissing it cancels the navigation, and its close
  # does not say how it was handled, so submit then returns like click.
  @impl true
  def submit(%Session{} = session, %Locator{} = locator, options \\ []) do
    %{page: page, frame: frame} = Session.page_state(session)

    locator_action(session, :submit, locator, options, fn native, remaining ->
      deadline = Deadline.new(remaining)

      # Listening first misses no request the submit starts.
      Listeners.listening(submission_listeners(page, frame), fn ref ->
        case BrowserLocator.evaluate(native, @submit, nil, timeout: remaining) do
          {:ok, true} -> await_submission(ref, deadline, remaining)
          {:ok, false} -> :ok
          {:error, error} -> {:error, error}
        end
      end)
    end)
  end

  # A navigation request comes before the frame commits to another document, so
  # a commit seen first navigated within the document. Listening for a dialog
  # would stop Playwright from handling it, so the wait listens for its close.
  defp submission_listeners(page, frame) do
    guid = frame.guid

    fn ref ->
      request = fn request ->
        if Request.is_navigation_request(request) and match?(%{guid: ^guid}, Events.request_frame(request)),
          do: send(ref, {ref, :request, request})
      end

      navigated = fn navigated -> if navigated.guid == guid, do: send(ref, {ref, :navigated}) end

      unload_prompted = fn dialog ->
        if PlaywrightEx.Dialog.type(dialog) == "beforeunload", do: send(ref, {ref, :unload_prompted})
      end

      [
        {BrowserPage, page, :request, request},
        {BrowserPage, page, :frame_navigated, navigated},
        {BrowserPage, page, :dialog_closed, unload_prompted}
      ]
    end
  end

  # Like Playwright's, a timeout message names the action's timeout.
  defp await_submission(ref, deadline, timeout) do
    receive do
      {^ref, :request, request} -> await_response(ref, request, deadline, timeout)
      {^ref, :navigated} -> :ok
      {^ref, :unload_prompted} -> :ok
    after
      Deadline.remaining(deadline, 1) ->
        {:error,
         %TimeoutError{
           message:
             "Timeout #{timeout}ms exceeded while waiting for the submitted form's navigation request; " <>
               "the browser sent none (a Content-Security-Policy form-action can block it silently)"
         }}
    end
  end

  # Reading the response has no timeout of its own; a failed request has none.
  # A redirect continues the navigation with another request.
  defp await_response(ref, request, deadline, timeout) do
    case Bounded.within(Deadline.remaining(deadline, 1), fn -> Request.response(request) end) do
      {:ok, {:ok, response}} ->
        if redirect?(response), do: await_submission(ref, deadline, timeout), else: :ok

      {:ok, {:error, error}} ->
        {:error, error}

      :timeout ->
        {:error, %TimeoutError{message: "Timeout #{timeout}ms exceeded while waiting for the form submission response"}}
    end
  end

  defp redirect?(nil), do: false

  defp redirect?(response),
    do: Response.status(response) in [301, 302, 303, 307, 308] and Map.has_key?(Response.headers(response), "location")

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

    locator_action(session, operation, locator, options, fn native, remaining ->
      # Only the activations after this point count, so the cursor is read
      # before the click even though the fallback below rarely needs it. Like
      # the read after the click, it is bookkeeping with the session's budget,
      # so a slow page neither loses the fallback nor shortens the click's.
      cursor = Document.activation_cursor(native, Session.timeout(session))

      case set.(native, native(options, remaining)) do
        # Playwright reads the state after its click, which a LiveView patch
        # may already have changed (in Firefox and WebKit it usually has). As on
        # Phoenix, the action succeeds once the click set the requested state.
        # The driver reports that as a plain `Error`, known only by its message;
        # check_action_test pins it.
        {:error, %PlaywrightError{message: message}} = error ->
          if message =~ "Clicking the checkbox did not change its state" and
               Document.activated?(native, cursor, desired, Session.timeout(session)),
             do: :ok,
             else: error

        result ->
          result
      end
    end)
  end

  @impl true
  def select_option(%Session{} = session, %Locator{} = locator, requested, options \\ []) do
    locator_action(
      session,
      :select_option,
      locator,
      options,
      &BrowserLocator.select_option(&1, uniform_option_values(requested), native(options, &2))
    )
  end

  # Playwright takes either strings (matching value or label) or option maps,
  # so a mixed list spells its strings as maps.
  defp uniform_option_values(values) do
    if Enum.all?(values, &is_binary/1),
      do: values,
      else: Enum.map(values, &if(is_binary(&1), do: %{valueOrLabel: &1}, else: &1))
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

  def screenshot(session, locator, path, options) do
    options =
      options
      |> Keyword.put(:path, path)
      |> Keyword.replace_lazy(:mask, fn mask -> Enum.map(mask, &locator(session, &1)) end)

    locator_action(session, :screenshot, locator, options, &BrowserLocator.screenshot(&1, native(options, &2)))
  end

  # Page-wide input and emulation have no timeout of their own and wait while a
  # script blocks the page. Unlike a locator action, Playwright does not wait for
  # a navigation the input starts, which may commit after this returns; the
  # next call adopts it then.
  def page_action(%Session{} = session, operation, fun, options) do
    page = Session.page_state(session).page

    action(session, operation, nil, options, fn remaining ->
      case Bounded.within(remaining, fn -> fun.(page) end) do
        {:ok, result} ->
          result

        :timeout ->
          {:error, %TimeoutError{message: "Timeout #{remaining}ms exceeded during #{operation}"}}
      end
    end)
  end

  @impl true
  def unwrap(%Session{} = session, fun) when is_function(fun, 1),
    do: run_unwrapped(session, Session.page_state(session).page, fun)

  # Like unwrap/2, with the locator resolved in the current frame.
  def unwrap_locator(%Session{} = session, %Locator{} = locator, fun) when is_function(fun, 1),
    do: run_unwrapped(session, locator(session, locator), fun)

  defp run_unwrapped(session, native, fun) do
    page = Session.page_state(session).page
    context = Session.context(session)

    {:ok, :unwrap, outcome} =
      navigation_aware_action(session, context.timeout, fn _remaining ->
        _ignored = fun.(native)
        validate_unwrapped!(context.browser_context, page)
        {:ok, :unwrap}
      end)

    outcome
  end

  # A clock call has no timeout of its own and waits while a timer it fires
  # blocks the page. Those timers can patch or navigate, as an action can.
  def clock(%Session{} = session, operation, fun, options) do
    clock = BrowserPage.clock(Session.page_state(session).page)
    timeout = Session.timeout(session, options)

    {:ok, :clock, outcome} =
      navigation_aware_action(session, timeout, fn remaining ->
        Bounded.within!(remaining, operation, fn -> with :ok <- fun.(clock), do: {:ok, :ok} end)
        {:ok, :clock}
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

  defp locator(session, locator), do: PlaywrightLocator.locator(Session.page_state(session).frame, locator)

  # Fluffy's own options stay here; the rest pass through to the PlaywrightEx call.
  defp native(options, remaining), do: Keyword.put(options, :timeout, remaining)

  defp locator_action(session, operation, locator, options, fun) do
    native = locator(session, locator)
    action(session, operation, locator, options, &fun.(native, &1))
  end

  defp action(session, operation, target, options, fun) do
    timeout = Session.timeout(session, options)

    case navigation_aware_action(session, timeout, &result(fun.(&1)), reuse_read?: true) do
      {:ok, _value, outcome} -> outcome
      {:error, error} -> OperationFailure.raise_playwright!(operation, target, error)
    end
  end

  defp result(:ok), do: {:ok, :ok}
  defp result(result), do: result

  # Only an action may reuse the previous read: its call gives up on a blocked
  # page after its own timeout. An expectation does not, so its read comes first.
  defp navigation_aware_action(session, operation_timeout, action, options \\ []) do
    # Browser bookkeeping has its own budget; it must not consume a short
    # action/assertion timeout or silently leave navigation state stale.
    {session, before} = prepare_document(session, options[:reuse_read?] == true)
    state = Session.page_state(session)
    browser_context = Session.context(session).browser_context
    bookkeeping_timeout = Session.timeout(session)

    case action.(operation_timeout) do
      {:ok, value} ->
        deadline = Deadline.new(bookkeeping_timeout)
        {:ok, value, reconcile_action_navigation(session, state, before, deadline)}

      # Playwright intends an action that closes its own page to succeed, but
      # Firefox can fail it. The page was open before the action.
      {:error, %TargetClosedError{} = error} ->
        if closed_own_page?(browser_context, state.page, bookkeeping_timeout),
          do: {:ok, nil, session},
          else: {:error, error}

      {:error, error} ->
        report_reused_read(state, before, bookkeeping_timeout)
        {:error, error}
    end
  end

  # An action that reused the previous read has not asked the page anything
  # itself. If it fails, a page that has since blocked is reported as its own
  # read would have reported it; a responsive page leaves the action's error.
  @reused_read_timeout 300
  defp report_reused_read(state, %{reused?: true}, timeout) do
    Document.probe!(state.frame, nil, min(timeout, @reused_read_timeout))
    :ok
  rescue
    TargetClosedError -> :ok
  end

  defp report_reused_read(_state, _before, _timeout), do: :ok

  # A lost driver or a closed context closes the page too. The context's
  # closed flag may still lag a lost driver, unlike a call on it. The page's
  # close event may still be on its way when the action fails; a call on the
  # page tells whether it is closed without waiting for it.
  defp closed_own_page?(browser_context, page, timeout) do
    deadline = Deadline.new(timeout)

    not BrowserContext.is_closed(browser_context) and
      match?({:ok, {:ok, _cookies}}, Bounded.within(timeout, fn -> BrowserContext.cookies(browser_context, []) end)) and
      page_closes?(page, deadline)
  end

  defp page_closes?(page, deadline) do
    listen = fn ref -> [{BrowserPage, page, :close, fn _page -> send(ref, {ref, :closed}) end}] end

    Listeners.listening(listen, fn ref ->
      BrowserPage.is_closed(page) or
        (target_closed?(page, deadline) and
           receive do
             {^ref, :closed} -> true
           after
             Deadline.remaining(deadline) -> false
           end)
    end)
  end

  defp target_closed?(page, deadline) do
    frame = BrowserPage.main_frame(page)
    read = Bounded.within(Deadline.remaining(deadline, 1), fn -> Frame.evaluate(frame, "1") end)
    match?({:ok, {:error, %TargetClosedError{}}}, read)
  end

  # When the previous action read this document and the main frame has not
  # navigated since, its read is this action's. Otherwise adopts a document
  # Fluffy has not seen: a new page's first document, or a navigation that
  # happened outside Fluffy (a late one, or through unwrap/2).
  defp prepare_document(session, reuse_read?) do
    state = Session.page_state(session)

    with true <- reuse_read?,
         false <- BrowserPage.is_closed(state.page),
         %{} = before <- Document.take_kept_probe(state) do
      {session, before}
    else
      _unavailable -> read_document(session, state, Session.timeout(session))
    end
  end

  defp read_document(session, state, timeout) do
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
    Document.adopted_probe!(state, nil, timeout)
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
    probe = Document.adopted_probe!(state, before.cursor, Deadline.remaining(deadline, 1))

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
        session = Session.put_page_state(session, %{state | kept_probe: probe})
        Document.keep_probe(state)
        session
    end
  end

  defp files({:local_paths, paths}), do: paths

  defp files({:payloads, payloads}) do
    Enum.map(payloads, &%{name: &1.name, mimeType: &1.content_type, buffer: &1.bytes})
  end
end
