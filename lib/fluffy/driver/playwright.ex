defmodule Fluffy.Driver.Playwright do
  @moduledoc false

  @behaviour Fluffy.Driver.Contract

  alias Fluffy.Deadline
  alias Fluffy.Expect
  alias Fluffy.FileChooser
  alias Fluffy.Internal.Navigation
  alias Fluffy.Internal.OperationFailure
  alias Fluffy.Locator
  alias Fluffy.Locator.Playwright, as: PlaywrightLocator
  alias Fluffy.Playwright.Diagnostics
  alias Fluffy.Playwright.Handle
  alias Fluffy.Playwright.Response
  alias Fluffy.Session
  alias Fluffy.URLMatcher
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.ElementHandle
  alias PlaywrightEx.FilePayload, as: BrowserFilePayload
  alias PlaywrightEx.Frame
  alias PlaywrightEx.Locator, as: BrowserLocator
  alias PlaywrightEx.Page, as: BrowserPage
  alias PlaywrightEx.Serialization

  @impl true
  def validate_operation!(_session, _operation, _arguments), do: :ok

  @impl true
  def expect(%Session{} = session, %Expect{} = expectation) do
    action_timeout = timeout_for(expectation)

    {:ok, :expectation, outcome} =
      navigation_aware_action(session, action_timeout, fn remaining ->
        expectation = Expect.merge_options(expectation, timeout: remaining)
        execute_expectation(session, expectation)
        {:ok, :expectation}
      end)

    outcome
  end

  defp execute_expectation(session, expectation) do
    case expectation do
      %Expect{target: {:locator, locator}, kind: :count, expected: expected} ->
        frame_expect!(session, expectation,
          expression: "to.have.count",
          expected_number: expected,
          selector: PlaywrightLocator.selector(locator)
        )

      %Expect{target: {:locator, locator}, kind: :visible} ->
        frame_expect!(session, expectation,
          expression: "to.be.visible",
          selector: PlaywrightLocator.selector(locator)
        )

      %Expect{target: {:locator, locator}, kind: :disabled} ->
        frame_expect!(session, expectation,
          expression: "to.be.disabled",
          selector: PlaywrightLocator.selector(locator)
        )

      %Expect{target: {:locator, locator}, kind: :editable} ->
        frame_expect!(session, expectation,
          expression: "to.be.editable",
          selector: PlaywrightLocator.selector(locator)
        )

      %Expect{target: {:locator, locator}, kind: :enabled} ->
        frame_expect!(session, expectation,
          expression: "to.be.enabled",
          selector: PlaywrightLocator.selector(locator)
        )

      %Expect{target: {:locator, locator}, kind: :focused} ->
        frame_expect!(session, expectation,
          expression: "to.be.focused",
          selector: PlaywrightLocator.selector(locator)
        )

      %Expect{target: {:locator, locator}, kind: :checked, expected: expected} ->
        frame_expect!(session, expectation,
          expression: "to.be.checked",
          expected_value: Serialization.serialize_arg(checked_expected_value(expected)),
          selector: PlaywrightLocator.selector(locator)
        )

      %Expect{target: {:locator, locator}, kind: :value, expected: expected} ->
        frame_expect!(session, expectation,
          expression: "to.have.value",
          expected_text: [expected_text(expected)],
          selector: PlaywrightLocator.selector(locator)
        )

      %Expect{target: {:locator, locator}, kind: :values, expected: expected} ->
        frame_expect!(session, expectation,
          expression: "to.have.values",
          expected_text: Enum.map(expected, &expected_text/1),
          selector: PlaywrightLocator.selector(locator)
        )

      %Expect{target: :page, kind: :url, expected: expected} ->
        page_url_expect!(session, expectation, expected)

      %Expect{target: :page, kind: :title, expected: expected} ->
        frame_expect!(session, expectation,
          expression: "to.have.title",
          expected_text: [expected_title(expected)]
        )
    end

    :ok
  end

  @impl true
  def set_html(%Session{} = session, html) when is_binary(html) do
    state = Session.page_state(session)

    {:ok, _result} =
      Frame.evaluate(state.frame_id,
        expression: "html => { document.querySelector('#fluffy-test-root').innerHTML = html }",
        is_function: true,
        arg: html,
        timeout: timeout()
      )

    session
  end

  @impl true
  def click(%Session{} = session, %Locator{} = locator, options \\ []) do
    options = Keyword.validate!(options, [:timeout])
    state = Session.page_state(session)
    action_timeout = options |> Keyword.get(:timeout, timeout()) |> max(1)

    case navigation_aware_action(session, action_timeout, fn remaining ->
           Frame.click(state.frame_id,
             selector: PlaywrightLocator.selector(locator),
             strict: true,
             timeout: remaining
           )
         end) do
      {:ok, _result, outcome} ->
        outcome

      {:error, error} ->
        OperationFailure.raise_playwright!(:click, locator, error)
    end
  end

  @impl true
  def submit(%Session{} = session, %Locator{} = locator, options \\ []) do
    options = Keyword.validate!(options, [:timeout])
    action_timeout = options |> Keyword.get(:timeout, timeout()) |> max(1)

    case navigation_aware_action(session, action_timeout, fn remaining ->
           BrowserLocator.evaluate(
             Session.page_state(session).frame_id,
             connection: session.context.connection,
             selector: PlaywrightLocator.selector(locator),
             expression: """
             form => {
               if (form.localName !== 'form')
                 throw new Error(`submit/2 requires a form locator, got ${form.localName}`)
               form.requestSubmit()
             }
             """,
             is_function: true,
             timeout: remaining
           )
         end) do
      {:ok, _result, outcome} ->
        outcome

      {:error, error} ->
        OperationFailure.raise_playwright!(:submit, locator, error)
    end
  end

  @impl true
  def fill(%Session{} = session, %Locator{} = locator, value, options \\ []) when is_binary(value) do
    options = Keyword.validate!(options, [:timeout])
    state = Session.page_state(session)
    action_timeout = options |> Keyword.get(:timeout, timeout()) |> max(1)

    case navigation_aware_action(session, action_timeout, fn remaining ->
           Frame.fill(state.frame_id,
             selector: PlaywrightLocator.selector(locator),
             strict: true,
             value: value,
             timeout: remaining
           )
         end) do
      {:ok, _result, outcome} ->
        outcome

      {:error, error} ->
        OperationFailure.raise_playwright!(:fill, locator, error)
    end
  end

  @impl true
  def set_input_files(%Session{} = session, %Locator{} = locator, source, _selected_files, options) do
    options = Keyword.validate!(options, [:timeout])
    state = Session.page_state(session)
    action_timeout = options |> Keyword.get(:timeout, timeout()) |> max(1)

    selector = PlaywrightLocator.selector(locator)

    result =
      navigation_aware_action(session, action_timeout, fn remaining ->
        Frame.set_input_files(
          state.frame_id,
          [selector: selector, strict: true, timeout: remaining] ++ selection_options(source)
        )
      end)

    case result do
      {:ok, _result, outcome} ->
        outcome

      {:error, error} ->
        OperationFailure.raise_playwright!(:set_input_files, locator, error)
    end
  end

  def set_input_files(%Session{} = session, key, source, _selected_files, options) when is_atom(key) do
    options = Keyword.validate!(options, [:timeout])
    chooser = Session.fetch_result!(session, key, :file_chooser)
    ensure_chooser_page!(session, chooser, key)
    action_timeout = options |> Keyword.get(:timeout, timeout()) |> max(1)

    result =
      navigation_aware_action(session, action_timeout, fn remaining ->
        ElementHandle.set_input_files(
          chooser.element_id,
          [connection: session.context.connection, timeout: remaining] ++
            selection_options(source)
        )
      end)

    case result do
      {:ok, _result, outcome} ->
        outcome

      {:error, error} ->
        OperationFailure.raise_playwright!(:set_input_files, key, error)
    end
  end

  @impl true
  def set_checked(%Session{} = session, %Locator{} = locator, desired, options \\ []) when is_boolean(desired) do
    options = Keyword.validate!(options, [:timeout])
    state = Session.page_state(session)
    action_timeout = options |> Keyword.get(:timeout, timeout()) |> max(1)
    action = if desired, do: :check, else: :uncheck

    result =
      navigation_aware_action(session, action_timeout, fn remaining ->
        apply(Frame, action, [
          state.frame_id,
          [
            selector: PlaywrightLocator.selector(locator),
            strict: true,
            timeout: remaining
          ]
        ])
      end)

    case result do
      {:ok, _result, outcome} ->
        outcome

      {:error, error} ->
        OperationFailure.raise_playwright!(action, locator, error)
    end
  end

  @impl true
  def select_option(%Session{} = session, %Locator{} = locator, requested, options \\ []) do
    options = Keyword.validate!(options, [:timeout])
    state = Session.page_state(session)
    action_timeout = options |> Keyword.get(:timeout, timeout()) |> max(1)

    result =
      navigation_aware_action(session, action_timeout, fn remaining ->
        Frame.select_option(state.frame_id,
          selector: PlaywrightLocator.selector(locator),
          strict: true,
          options: protocol_options(requested),
          timeout: remaining
        )
      end)

    case result do
      {:ok, _values, outcome} ->
        outcome

      {:error, error} ->
        OperationFailure.raise_playwright!(:select_option, locator, error)
    end
  end

  @impl true
  def focus(%Session{} = session, %Locator{} = locator, options \\ []) do
    element_action(session, locator, :focus, options)
  end

  @impl true
  def blur(%Session{} = session, %Locator{} = locator, options \\ []) do
    element_action(session, locator, :blur, options)
  end

  @impl true
  def press(%Session{} = session, %Locator{} = locator, key, options \\ []) do
    options = Keyword.validate!(options, delay: 0, timeout: timeout())
    state = Session.page_state(session)

    action_timeout = max(options[:timeout], 1)

    case navigation_aware_action(session, action_timeout, fn remaining ->
           Frame.press(state.frame_id,
             selector: PlaywrightLocator.selector(locator),
             key: key,
             delay: options[:delay],
             timeout: remaining
           )
         end) do
      {:ok, _result, outcome} ->
        outcome

      {:error, error} ->
        OperationFailure.raise_playwright!(:press, locator, error)
    end
  end

  @impl true
  def unwrap(%Session{} = session, fun) when is_function(fun, 1) do
    state = Session.page_state(session)

    handle = %Handle{
      context_id: session.context.context_id,
      page_id: state.page_id,
      frame_id: state.frame_id,
      connection: session.context.connection,
      timeout: session.context.timeout
    }

    {:ok, :unwrap, outcome} =
      navigation_aware_action(session, session.context.timeout, fn _remaining ->
        _ignored = fun.(handle)
        validate_unwrapped_handle!(handle)
        {:ok, :unwrap}
      end)

    outcome
  end

  defp frame_expect!(%Session{} = session, %Expect{} = expectation, options) do
    state = Session.page_state(session)
    timeout = expectation.options |> Keyword.get(:timeout, timeout()) |> max(1)

    options =
      Keyword.merge([connection: session.context.connection, is_not: expectation.negated?, timeout: timeout], options)

    case Frame.expect_result(state.frame_id, options) do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        raise ExUnit.AssertionError,
          message: "Expected #{Expect.describe(expectation)}\n" <> Diagnostics.format(error)
    end
  end

  defp page_url_expect!(%Session{} = session, %Expect{} = expectation, expected) do
    state = Session.page_state(session)
    timeout = Keyword.get(expectation.options, :timeout, timeout())
    matcher = fn uri -> URLMatcher.matches?(expected, URI.to_string(uri)) != expectation.negated? end

    case Frame.wait_for_url(state.frame_id,
           connection: session.context.connection,
           url: matcher,
           wait_until: "commit",
           timeout: timeout
         ) do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        {:ok, %{url: actual}} = Frame.snapshot(state.frame_id, connection: session.context.connection)

        raise ExUnit.AssertionError,
          message: "Expected #{Expect.describe(expectation)}, got #{inspect(actual)}\n" <> Diagnostics.format(error)
    end
  end

  defp navigation_aware_action(session, operation_timeout, action) do
    # Browser bookkeeping has its own budget; it must not consume a short
    # action/assertion timeout or silently leave navigation state stale.
    deadline = Deadline.new(max(session.context.timeout, 1))
    state = Session.page_state(session)

    previous_url = Session.current_page(session).url
    navigation_cursor = live_navigation_cursor(state, Deadline.remaining(deadline, 1))

    case action.(operation_timeout) do
      {:ok, value} ->
        outcome =
          reconcile_action_navigation(
            session,
            state,
            previous_url,
            navigation_cursor,
            Deadline.new(max(session.context.timeout, 1))
          )

        {:ok, value, outcome}

      {:error, error} ->
        {:error, error}
    end
  end

  defp reconcile_action_navigation(session, state, previous_url, navigation_cursor, deadline) do
    {:ok, snapshot} = Frame.snapshot(state.frame_id, connection: session.context.connection)

    if snapshot.url == previous_url and snapshot.document_ref == state.document_identity do
      session
    else
      {:navigate, session, browser_navigation(state, snapshot, navigation_cursor, session.context.connection, deadline)}
    end
  end

  defp browser_navigation(state, snapshot, navigation_cursor, connection, deadline) do
    if snapshot.document_ref == state.document_identity do
      case live_navigation_kind(state, navigation_cursor, Deadline.remaining(deadline, 1)) do
        :redirect -> Navigation.browser_committed(snapshot.url, state, live_navigation_cursor: navigation_cursor)
        _patch -> Navigation.browser_patch(snapshot.url, state)
      end
    else
      response = await_navigation_response!(snapshot.document_request, connection, deadline)
      state = %{state | document_identity: snapshot.document_ref}
      Navigation.browser_committed(snapshot.url, state, response: response)
    end
  end

  defp await_navigation_response!(request, connection, deadline) do
    case Response.for_request(request, connection: connection, timeout: Deadline.remaining(deadline, 1)) do
      {:ok, response} -> response
      {:error, reason} -> raise "Could not capture the final main-document response: #{inspect(reason)}"
    end
  end

  defp live_navigation_cursor(state, operation_timeout) do
    case Frame.evaluate(state.frame_id,
           expression: "() => window.__fluffyLiveNavigationEvents?.length ?? 0",
           is_function: true,
           timeout: operation_timeout
         ) do
      {:ok, cursor} when is_integer(cursor) -> cursor
      {:ok, _unexpected} -> 0
      {:error, _error} -> 0
    end
  end

  defp live_navigation_kind(state, cursor, operation_timeout) do
    case Frame.evaluate(state.frame_id,
           expression: """
           cursor => window.__fluffyLiveNavigationEvents?.slice(cursor).at(-1)?.kind ?? 'document'
           """,
           is_function: true,
           arg: cursor,
           timeout: operation_timeout
         ) do
      {:ok, "patch"} -> :patch
      {:ok, "redirect"} -> :redirect
      _otherwise -> :document
    end
  end

  defp timeout_for(%Expect{} = expectation) do
    Keyword.get(expectation.options, :timeout, timeout())
  end

  defp checked_expected_value(:checked), do: %{checked: true}
  defp checked_expected_value(:unchecked), do: %{checked: false}
  defp checked_expected_value(:indeterminate), do: %{indeterminate: true}

  defp validate_unwrapped_handle!(%Handle{} = handle) do
    case BrowserContext.cookies(handle.context_id,
           connection: handle.connection,
           timeout: max(handle.timeout, 1)
         ) do
      {:ok, _cookies} -> :ok
      {:error, error} -> invalidated_handle!(:context, error)
    end

    case BrowserPage.bring_to_front(handle.page_id,
           connection: handle.connection,
           timeout: max(handle.timeout, 1)
         ) do
      {:ok, _result} -> :ok
      {:error, error} -> invalidated_handle!(:page, error)
    end
  end

  defp invalidated_handle!(kind, error) do
    raise ArgumentError,
          "Playwright unwrap invalidated the tracked #{kind}; use Fluffy page and session lifecycle APIs: #{inspect(error, limit: :infinity)}"
  end

  defp expected_text(value) do
    %{
      string: value,
      ignore_case: false,
      match_substring: false,
      normalize_white_space: false
    }
  end

  defp expected_title(value) when is_binary(value) do
    %{
      string: value,
      ignore_case: false,
      match_substring: false,
      normalize_white_space: true
    }
  end

  defp expected_title(%Regex{source: source, opts: opts}) do
    %{
      regex_source: source,
      regex_flags: Serialization.regex_flags_for_protocol(opts),
      ignore_case: false,
      match_substring: false,
      normalize_white_space: true
    }
  end

  defp protocol_options(requested) do
    requested
    |> List.wrap()
    |> Enum.map(fn
      option when is_binary(option) -> %{value_or_label: option}
      %{value: value} -> %{value: value}
      %{label: label} -> %{label: label}
      %{index: index} -> %{index: index}
    end)
  end

  defp element_action(session, locator, action, options) do
    options = Keyword.validate!(options, [:timeout])
    state = Session.page_state(session)
    action_timeout = options |> Keyword.get(:timeout, timeout()) |> max(1)

    result =
      navigation_aware_action(session, action_timeout, fn remaining ->
        apply(Frame, action, [
          state.frame_id,
          [selector: PlaywrightLocator.selector(locator), timeout: remaining]
        ])
      end)

    case result do
      {:ok, _result, outcome} ->
        outcome

      {:error, error} ->
        OperationFailure.raise_playwright!(action, locator, error)
    end
  end

  defp selection_options({:local_paths, paths}), do: [local_paths: paths]

  defp selection_options({:payloads, payloads}) do
    [
      payloads:
        Enum.map(payloads, fn payload ->
          %BrowserFilePayload{
            name: payload.name,
            buffer: payload.bytes,
            mime_type: payload.content_type
          }
        end)
    ]
  end

  defp ensure_chooser_page!(session, %FileChooser{page_id: page_id}, key) do
    if Session.page_state(session).page_id != page_id do
      raise ArgumentError,
            "captured file chooser #{inspect(key)} belongs to a page other than the active page"
    end
  end

  defp timeout do
    :fluffy
    |> Application.fetch_env!(:playwright)
    |> Keyword.fetch!(:timeout)
  end
end
