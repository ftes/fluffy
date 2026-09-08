defmodule Fluffy.Driver.Playwright do
  @moduledoc false

  @behaviour Fluffy.Driver.Contract

  import ExUnit.Assertions

  alias Fluffy.Actionability
  alias Fluffy.ClientDOM
  alias Fluffy.Expect
  alias Fluffy.Expectation
  alias Fluffy.FileChooser
  alias Fluffy.Internal.Navigation
  alias Fluffy.Locator
  alias Fluffy.Locator.Playwright, as: PlaywrightLocator
  alias Fluffy.Locator.Static, as: StaticLocator
  alias Fluffy.Playwright.Handle
  alias Fluffy.Playwright.NavigationObserver
  alias Fluffy.Session
  alias Fluffy.URLMatcher
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.ElementHandle
  alias PlaywrightEx.FilePayload, as: BrowserFilePayload
  alias PlaywrightEx.Frame
  alias PlaywrightEx.Page, as: BrowserPage
  alias PlaywrightEx.Serialization

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
        result =
          frame_expect(session, expectation,
            expression: "to.have.count",
            expected_number: expected,
            selector: PlaywrightLocator.selector(locator)
          )

        if result != {:ok, not expectation.negated?} do
          if expectation.negated? do
            raise ExUnit.AssertionError,
              message: "Expected #{Expect.describe(expectation)}, got #{inspect(result)}"
          else
            Expectation.raise_count!(locator, expected, snapshot_candidates(session, locator))
          end
        end

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
        case snapshot_candidates(session, locator) do
          [element] ->
            ensure_snapshot_enabled!(session, locator, :click)
            Actionability.ensure_clickable!(element, :click, locator)
            raise "Playwright click failed: #{inspect(error)}"

          candidates ->
            raise Fluffy.StrictnessError, locator: locator, candidates: candidates
        end
    end
  end

  @impl true
  def submit(%Session{} = session, %Locator{} = locator, options \\ []) do
    options = Keyword.validate!(options, [:timeout])
    state = Session.page_state(session)
    action_timeout = options |> Keyword.get(:timeout, timeout()) |> max(1)
    target = form_target!(session, locator, action_timeout)

    case navigation_aware_action(session, action_timeout, fn remaining ->
           Frame.evaluate(state.frame_id,
             expression: """
             selector => {
               const form = document.querySelector(selector)
               if (!form) throw new Error(`Fluffy form target disappeared: ${selector}`)
               form.requestSubmit()
             }
             """,
             is_function: true,
             arg: target.selector,
             timeout: remaining
           )
         end) do
      {:ok, _result, outcome} ->
        outcome

      {:error, error} ->
        raise "Playwright submit failed: #{inspect(error)}"
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
        case snapshot_candidates(session, locator) do
          [element] ->
            ensure_snapshot_enabled!(session, locator, :fill)
            Actionability.ensure_editable!(element, :fill, locator)
            raise "Playwright fill failed: #{inspect(error)}"

          candidates ->
            raise Fluffy.StrictnessError, locator: locator, candidates: candidates
        end
    end
  end

  @impl true
  def set_input_files(%Session{} = session, %Locator{} = locator, source, selected_files, options) do
    options = Keyword.validate!(options, [:timeout])
    state = Session.page_state(session)
    action_timeout = options |> Keyword.get(:timeout, timeout()) |> max(1)

    case snapshot_candidates(session, locator) do
      [element] ->
        Actionability.ensure_file_input_files!(
          element,
          selected_files,
          :set_input_files,
          locator
        )

      _not_one_target ->
        :ok
    end

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
        case snapshot_candidates(session, locator) do
          [_element] -> raise "Playwright set_input_files failed: #{inspect(error)}"
          candidates -> raise Fluffy.StrictnessError, locator: locator, candidates: candidates
        end
    end
  end

  def set_input_files(%Session{} = session, key, source, selected_files, options) when is_atom(key) do
    options = Keyword.validate!(options, [:timeout])
    chooser = Session.fetch_result!(session, key, :file_chooser)
    ensure_chooser_page!(session, chooser, key)
    ensure_chooser_accepts_files!(chooser, selected_files, key)
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
      {:ok, _result, outcome} -> outcome
      {:error, error} -> raise "Playwright file chooser set_input_files failed: #{inspect(error)}"
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
        case snapshot_candidates(session, locator) do
          [element] ->
            ensure_snapshot_enabled!(session, locator, action)
            classify_checked_failure!(element, action, locator)
            raise "Playwright #{action} failed: #{inspect(error)}"

          candidates ->
            raise Fluffy.StrictnessError, locator: locator, candidates: candidates
        end
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
        case snapshot_candidates(session, locator) do
          [element] ->
            ensure_snapshot_enabled!(session, locator, :select_option)
            classify_select_failure!(element, requested, locator)
            raise "Playwright select_option failed: #{inspect(error)}"

          candidates ->
            raise Fluffy.StrictnessError, locator: locator, candidates: candidates
        end
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
        case snapshot_candidates(session, locator) do
          [_element] -> raise "Playwright press failed: #{inspect(error)}"
          candidates -> raise Fluffy.StrictnessError, locator: locator, candidates: candidates
        end
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

  defp snapshot_candidates(session, locator) do
    state = Session.page_state(session)

    case Frame.content(state.frame_id, timeout: timeout()) do
      {:ok, html} ->
        html
        |> LazyHTML.from_document()
        |> StaticLocator.resolve(locator)

      {:error, _error} ->
        []
    end
  end

  defp form_target!(session, locator, action_timeout) do
    state = Session.page_state(session)

    case Frame.content(state.frame_id, timeout: action_timeout) do
      {:ok, html} ->
        target = html |> ClientDOM.from_document() |> ClientDOM.target!(locator)

        if target.tag == "form" do
          target
        else
          raise ArgumentError, "submit/2 requires a form locator, got #{inspect(target.tag)}"
        end

      {:error, error} ->
        raise "Could not resolve Playwright form target: #{inspect(error)}"
    end
  end

  defp ensure_snapshot_enabled!(session, locator, action) do
    state = Session.page_state(session)

    with {:ok, html} <- Frame.content(state.frame_id, timeout: timeout()),
         %{disabled?: true} <- html |> ClientDOM.from_document() |> ClientDOM.target!(locator) do
      raise Fluffy.ActionabilityError,
        action: action,
        reason: :disabled,
        locator: locator
    else
      _enabled_or_unavailable -> :ok
    end
  end

  defp frame_expect!(%Session{} = session, %Expect{} = expectation, options) do
    result = frame_expect(session, expectation, options)
    expected_result = {:ok, not expectation.negated?}

    assert result == expected_result,
           "Expected #{Expect.describe(expectation)}, got #{inspect(result)}"
  rescue
    error in ExUnit.AssertionError ->
      reraise(error, __STACKTRACE__)
  end

  defp frame_expect(%Session{} = session, %Expect{} = expectation, options) do
    state = Session.page_state(session)
    timeout = expectation.options |> Keyword.get(:timeout, timeout()) |> max(1)
    options = Keyword.merge([is_not: expectation.negated?, timeout: timeout], options)

    Frame.expect(state.frame_id, options)
  end

  defp page_url_expect!(%Session{} = session, %Expect{} = expectation, expected) do
    state = Session.page_state(session)
    timeout = expectation.options |> Keyword.get(:timeout, timeout()) |> max(1)
    deadline = System.monotonic_time(:millisecond) + timeout

    poll_url_expectation!(state, expectation, expected, deadline)
  end

  defp poll_url_expectation!(state, expectation, expected, deadline) do
    actual = current_url(state, remaining(deadline))
    passed? = URLMatcher.matches?(expected, actual)

    cond do
      passed? != expectation.negated? ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        raise ExUnit.AssertionError,
          message: "Expected #{Expect.describe(expectation)}, got #{inspect(actual)}"

      true ->
        receive do
        after
          min(10, remaining(deadline)) ->
            poll_url_expectation!(state, expectation, expected, deadline)
        end
    end
  end

  defp navigation_aware_action(session, operation_timeout, action) do
    deadline = System.monotonic_time(:millisecond) + max(operation_timeout, 1)
    state = Session.page_state(session)

    observer =
      state.navigation_observer ||
        NavigationObserver.arm(
          session.context.context_id,
          state.page_id,
          state.frame_id,
          remaining(deadline)
        )

    previous_url = Session.current_page(session).url || current_url(state, remaining(deadline))
    navigation_cursor = live_navigation_cursor(state, remaining(deadline))

    try do
      case action.(remaining(deadline)) do
        {:ok, value} ->
          outcome =
            reconcile_action_navigation(
              session,
              state,
              previous_url,
              navigation_cursor,
              observer,
              deadline
            )

          {:ok, value, outcome}

        {:error, error} ->
          {:error, error}
      end
    rescue
      error ->
        reraise(error, __STACKTRACE__)
    end
  end

  defp reconcile_action_navigation(session, state, previous_url, navigation_cursor, observer, deadline) do
    case read_current_url(state, deadline) do
      {:error, error} ->
        if System.monotonic_time(:millisecond) >= deadline and
             String.contains?(playwright_error_message(error), "Timeout") do
          session
        else
          raise "Could not read the current browser URL: #{inspect(error)}"
        end

      {:ok, ^previous_url} ->
        Session.put_page_state(session, %{state | navigation_observer: observer})

      {:ok, url} ->
        {:navigate, session,
         browser_navigation(
           state,
           previous_url,
           url,
           navigation_cursor,
           observer,
           deadline
         )}
    end
  end

  defp read_current_url(state, deadline) do
    do_read_current_url(state, deadline)
  end

  defp do_read_current_url(state, deadline) do
    timeout = max(deadline - System.monotonic_time(:millisecond), 1)

    case Frame.evaluate(state.frame_id,
           expression: "() => location.href",
           is_function: true,
           timeout: timeout
         ) do
      {:ok, path} ->
        {:ok, path}

      {:error, error} ->
        if navigation_context_error?(error) and System.monotonic_time(:millisecond) < deadline do
          receive do
          after
            1 -> do_read_current_url(state, deadline)
          end
        else
          {:error, error}
        end
    end
  end

  defp browser_navigation(state, previous_url, url, navigation_cursor, observer, deadline) do
    case live_navigation_kind(state, navigation_cursor, remaining(deadline)) do
      :patch ->
        Navigation.browser_patch(url, %{state | navigation_observer: observer})

      :redirect ->
        if same_document_navigation?(state, previous_url, url, remaining(deadline)) do
          Navigation.browser_committed(url, %{state | navigation_observer: observer},
            live_navigation_cursor: navigation_cursor
          )
        else
          response = await_navigation_response!(observer, deadline)

          Navigation.browser_committed(url, state,
            live_navigation_cursor: navigation_cursor,
            response: response
          )
        end

      :document ->
        if same_document_navigation?(state, previous_url, url, remaining(deadline)) do
          Navigation.browser_patch(url, %{state | navigation_observer: observer})
        else
          response = await_navigation_response!(observer, deadline)
          Navigation.browser_committed(url, state, response: response)
        end
    end
  end

  defp await_navigation_response!(observer, deadline) do
    case NavigationObserver.await(observer, remaining(deadline)) do
      {:ok, response} ->
        response

      {:error, reason} ->
        raise "Could not capture the final main-document response: #{inspect(reason)}"
    end
  end

  defp same_document_navigation?(state, previous_url, url, operation_timeout) do
    previous_url != url and
      state.document_identity == document_identity(state, operation_timeout)
  end

  defp document_identity(state, operation_timeout) do
    case Frame.evaluate(state.frame_id,
           expression: "() => performance.timeOrigin",
           is_function: true,
           timeout: operation_timeout
         ) do
      {:ok, identity} -> identity
      {:error, _error} -> nil
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
    expectation.options |> Keyword.get(:timeout, timeout()) |> max(1)
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 1)

  defp checked_expected_value(:checked), do: %{checked: true}
  defp checked_expected_value(:unchecked), do: %{checked: false}
  defp checked_expected_value(:indeterminate), do: %{indeterminate: true}

  defp current_url(state, operation_timeout) do
    deadline = System.monotonic_time(:millisecond) + max(operation_timeout, 1)
    do_current_url(state, deadline)
  end

  defp do_current_url(state, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 1)

    case Frame.evaluate(state.frame_id,
           expression: "() => location.href",
           is_function: true,
           timeout: remaining
         ) do
      {:ok, path} ->
        path

      {:error, error} ->
        if navigation_context_error?(error) and
             System.monotonic_time(:millisecond) < deadline do
          receive do
          after
            1 -> do_current_url(state, deadline)
          end
        else
          raise "Could not read the current browser URL: #{inspect(error)}"
        end
    end
  end

  defp navigation_context_error?(error) do
    String.contains?(playwright_error_message(error), [
      "Execution context was destroyed",
      "Cannot find context with specified id"
    ])
  end

  defp playwright_error_message(%{error: %{message: message}}) when is_binary(message), do: message

  defp playwright_error_message(%{message: message}) when is_binary(message), do: message
  defp playwright_error_message(_error), do: ""

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
          "Playwright unwrap invalidated the tracked #{kind}; use Fluffy page and session lifecycle APIs: #{inspect(error)}"
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

  defp classify_checked_failure!(element, action, locator) do
    Actionability.ensure_checkable!(element, action, locator)

    if action == :uncheck and LazyHTML.tag(element) == ["input"] and
         LazyHTML.attribute(element, "type") == ["radio"] and
         LazyHTML.attribute(element, "checked") != [] do
      raise Fluffy.ActionabilityError,
        action: action,
        reason: :cannot_uncheck_radio,
        locator: locator
    end

    Actionability.ensure_enabled!(element, action, locator)
  end

  defp classify_select_failure!(element, requested, locator) do
    Actionability.ensure_selectable!(element, :select_option, locator)

    html = LazyHTML.to_html(element)
    client_dom = ClientDOM.from_fragment(html)
    select = Locator.new({:css, "select"})
    ClientDOM.select_option(client_dom, select, requested)
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
        case snapshot_candidates(session, locator) do
          [_element] -> raise "Playwright #{action} failed: #{inspect(error)}"
          candidates -> raise Fluffy.StrictnessError, locator: locator, candidates: candidates
        end
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

  defp ensure_chooser_accepts_files!(%FileChooser{multiple?: false}, [_, _ | _], key) do
    raise Fluffy.ActionabilityError,
      action: :set_input_files,
      reason: :multiple_files_not_allowed,
      target: "captured file chooser #{inspect(key)}"
  end

  defp ensure_chooser_accepts_files!(%FileChooser{}, _selected_files, _key), do: :ok

  defp timeout do
    :fluffy
    |> Application.fetch_env!(:playwright)
    |> Keyword.fetch!(:timeout)
  end
end
