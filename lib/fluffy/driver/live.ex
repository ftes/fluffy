defmodule Fluffy.Driver.Live do
  @moduledoc false

  @behaviour Fluffy.Driver.Contract

  import Phoenix.LiveViewTest

  alias Fluffy.ClientDOM
  alias Fluffy.Driver.Live.ActionResolver
  alias Fluffy.Driver.Live.Keyboard
  alias Fluffy.Driver.Live.Retry
  alias Fluffy.Driver.Live.UploadState
  alias Fluffy.Expect
  alias Fluffy.Form
  alias Fluffy.HTML.Semantics
  alias Fluffy.Internal.Navigation
  alias Fluffy.LiveViewTest.UploadCompat
  alias Fluffy.Locator
  alias Fluffy.Locator.Static, as: StaticLocator
  alias Fluffy.Page
  alias Fluffy.Session
  alias Fluffy.TestScope
  alias Fluffy.URLMatcher

  @retry_interval 10

  @impl true
  def expect(%Session{} = session, %Expect{} = expectation) do
    options = Keyword.validate!(expectation.options, [:timeout])

    eventually(session, options, fn session ->
      case evaluate_expectation(session, expectation) do
        {:ok, passed?, _actual} when passed? != expectation.negated? ->
          {:ok, session}

        {:ok, _passed?, actual} ->
          {:retry, "Expected #{Expect.describe(expectation)}, got #{inspect(actual)}"}
      end
    end)
  end

  @impl true
  def click(%Session{} = session, %Locator{} = locator, action_options \\ []) do
    case resolve_live_action(session, locator, action_options, fn client_dom ->
           ClientDOM.click(client_dom, locator)
         end) do
      {%Session{} = session, {client_dom, target}} -> commit_click(session, client_dom, target)
      navigation -> navigation
    end
  end

  defp commit_click(session, client_dom, target) do
    state = Session.page_state(session)
    event_context = owning_view_context(state.view, target)

    case ClientDOM.phoenix_html_submission(client_dom, target) do
      submission when is_map(submission) ->
        if competing_live_click_binding?(target) do
          raise Fluffy.CapabilityError,
            capability: :phoenix_html_live_action_conflict,
            driver: :live,
            detail:
              "a data-method/data-to link with a competing phx-click or LiveView navigation action requires Playwright"
        else
          {:navigate, Session.put_page_state(session, %{state | client_dom: client_dom}),
           Navigation.submission(submission)}
        end

      nil ->
        commit_plain_click(session, client_dom, target, event_context)
    end
  end

  defp competing_live_click_binding?(target) do
    Enum.any?([target | Enum.reverse(target.ancestors)], fn element ->
      not is_nil(attribute(element.attributes, "phx-click")) or
        not is_nil(attribute(element.attributes, "data-phx-link"))
    end)
  end

  defp commit_plain_click(session, client_dom, target, event_context) do
    state = Session.page_state(session)
    event_view = event_context.view

    case live_click_action(target) do
      :dispatch_change ->
        dispatch_live_click_change(session, client_dom, target, event_context)

      :render_click ->
        result =
          try do
            event_view
            |> element(selector_for_view(client_dom, target.selector, event_context))
            |> render_click()
          catch
            :exit, reason -> raise Fluffy.LiveViewError, reason: reason
          end

        case commit_render_result(session, client_dom, result, event_view) do
          %Session{} = session -> release_cancelled_live_upload(session, target)
          navigation -> navigation
        end

      :none ->
        session = Session.put_page_state(session, %{state | client_dom: client_dom})

        case ClientDOM.form_submission(client_dom, target, :live) do
          %{phx_submit?: true} = submission ->
            case live_upload_for_submit(session, target) do
              {:ok, form_id, upload} ->
                dispatch_live_upload_submit(
                  session,
                  client_dom,
                  form_id,
                  upload,
                  submission,
                  event_context
                )

              :none ->
                dispatch_live_submit(session, client_dom, submission, event_context)
            end

          %{phx_submit?: false} = submission ->
            {:navigate, session, Navigation.submission(submission)}

          nil ->
            case {target.tag, attribute(target.attributes, "href")} do
              {tag, href} when tag in ["a", "area"] and is_binary(href) ->
                {:navigate, session,
                 Navigation.link(href,
                   download: attribute(target.attributes, "download")
                 )}

              _other ->
                session
            end
        end
    end
  end

  defp dispatch_live_click_change(session, client_dom, target, event_context) do
    state = Session.page_state(session)
    event_view = event_context.view
    session = Session.put_page_state(session, %{state | client_dom: client_dom})

    case ClientDOM.dispatch_change_event(client_dom, target) do
      nil ->
        session

      event ->
        payload =
          event.fields
          |> Form.to_params()
          |> Map.put("_target", event.target_name || "undefined")
          |> decode_merge_target()

        result =
          try do
            event_view
            |> element(selector_for_view(client_dom, event.dispatcher_selector, event_context))
            |> render_change(payload)
          catch
            :exit, reason -> raise Fluffy.LiveViewError, reason: reason
          end

        commit_render_result(session, client_dom, result, event_view)
    end
  end

  @impl true
  def submit(%Session{} = session, %Locator{} = locator, options \\ []) do
    Keyword.validate!(options, [:timeout])
    state = Session.page_state(session)
    client_dom = Map.fetch!(state, :client_dom)
    target = ClientDOM.target!(client_dom, locator)
    event_context = owning_view_context(state.view, target)

    case ClientDOM.submit_form(client_dom, target, :live) do
      nil ->
        raise ArgumentError, "submit/2 requires a form locator, got #{inspect(target.tag)}"

      %{phx_submit?: true} = submission ->
        dispatch_live_submit(session, client_dom, submission, event_context)

      %{phx_submit?: false} = submission ->
        {:navigate, session, Navigation.submission(submission)}
    end
  end

  @impl true
  def fill(%Session{} = session, %Locator{} = locator, value, options \\ []) do
    case resolve_live_action(session, locator, options, &ClientDOM.fill(&1, locator, value)) do
      {%Session{} = session, {client_dom, target}} -> dispatch_live_change(session, client_dom, target)
      navigation -> navigation
    end
  end

  @impl true
  def set_input_files(%Session{} = session, %Locator{} = locator, _source_paths, selected_files, _options \\ []) do
    state = Session.page_state(session)

    if ClientDOM.live_managed_form?(state.client_dom, locator) do
      case selected_files do
        [_selected_file | _remaining_files] ->
          set_live_upload(session, locator, selected_files)

        [] ->
          client_dom = ClientDOM.set_input_files(state.client_dom, locator, [])
          Session.put_page_state(session, %{state | client_dom: client_dom})
      end
    else
      client_dom = ClientDOM.set_input_files(state.client_dom, locator, selected_files)
      Session.put_page_state(session, %{state | client_dom: client_dom})
    end
  end

  @doc false
  def release_page_uploads(%Session{} = session, %Page{driver: :live, state: state}) do
    state
    |> Map.fetch!(:live_uploads)
    |> UploadState.forms()
    |> Enum.each(&release_live_upload_clients(session, &1))

    :ok
  end

  def release_page_uploads(%Session{}, %Page{}), do: :ok

  @impl true
  def set_checked(%Session{} = session, %Locator{} = locator, desired, options \\ []) do
    case resolve_live_action(
           session,
           locator,
           options,
           &ClientDOM.set_checked(&1, locator, desired)
         ) do
      {%Session{} = session, {candidate_client_dom, target}} ->
        state = Session.page_state(session)

        if candidate_client_dom == state.client_dom do
          session
        else
          commit_checked(session, candidate_client_dom, target, locator)
        end

      navigation ->
        navigation
    end
  end

  defp commit_checked(session, client_dom, target, locator) do
    case commit_click(session, client_dom, target) do
      %Session{} = session ->
        dispatch_live_change(session, Session.page_state(session).client_dom, locator)

      navigation ->
        navigation
    end
  end

  @impl true
  def select_option(%Session{} = session, %Locator{} = locator, requested, options \\ []) do
    case resolve_live_action(
           session,
           locator,
           options,
           &ClientDOM.select_option(&1, locator, requested)
         ) do
      {%Session{} = session, {client_dom, target}} -> dispatch_live_change(session, client_dom, target)
      navigation -> navigation
    end
  end

  @impl true
  def focus(%Session{} = session, %Locator{} = locator, options \\ []) do
    Keyword.validate!(options, [:timeout])
    update_client_dom(session, &ClientDOM.focus(&1, locator))
  end

  @impl true
  def blur(%Session{} = session, %Locator{} = locator, options \\ []) do
    Keyword.validate!(options, [:timeout])
    update_client_dom(session, &ClientDOM.blur(&1, locator))
  end

  @impl true
  def press(%Session{} = session, %Locator{} = locator, key, options \\ []) do
    options = Keyword.validate!(options, [:delay, :timeout])
    resolve_options = Keyword.take(options, [:timeout])

    case resolve_live_action(session, locator, resolve_options, fn client_dom ->
           target = ClientDOM.target!(client_dom, locator)
           {ClientDOM.focus(client_dom, locator), target}
         end) do
      {%Session{} = session, {client_dom, target}} ->
        press_key(session, client_dom, target, locator, key)

      navigation ->
        navigation
    end
  end

  defp press_key(session, client_dom, target, locator, key) do
    state = Session.page_state(session)
    session = Session.put_page_state(session, %{state | client_dom: client_dom})
    submission = if key == "Enter", do: ClientDOM.implicit_submission(client_dom, locator, :live)

    with %Session{} = session <-
           dispatch_key_bindings(session, Keyboard.bindings(client_dom, target, :keydown, key)),
         %Session{} = session <- commit_key_default(session, locator, key, submission),
         %Session{} = session <- dispatch_keyup(session, target, key, submission) do
      commit_space_default(session, locator, key)
    end
  end

  defp dispatch_keyup(session, _target, key, %{phx_submit?: true}) do
    client_dom = client_dom(session)
    dispatch_key_bindings(session, Keyboard.window_bindings(client_dom, :keyup, key))
  end

  defp dispatch_keyup(session, _target, key, _submission) do
    client_dom = client_dom(session)

    bindings =
      case ClientDOM.focused_target(client_dom) do
        nil -> Keyboard.window_bindings(client_dom, :keyup, key)
        target -> Keyboard.bindings(client_dom, target, :keyup, key)
      end

    dispatch_key_bindings(session, bindings)
  end

  defp dispatch_key_bindings(session, bindings) do
    Enum.reduce_while(bindings, session, fn binding, session ->
      case dispatch_key_binding(session, binding) do
        %Session{} = session -> {:cont, session}
        navigation -> {:halt, navigation}
      end
    end)
  end

  defp dispatch_key_binding(session, %Keyboard{} = binding) do
    state = Session.page_state(session)
    event_context = owning_view_context(state.view, binding.target)
    event_view = event_context.view

    selector = selector_for_view(state.client_dom, binding.target.selector, event_context)

    result =
      try do
        event_element = element(event_view, selector)

        case binding.phase do
          :keydown -> render_keydown(event_element, binding.payload)
          :keyup -> render_keyup(event_element, binding.payload)
        end
      catch
        :exit, reason -> raise Fluffy.LiveViewError, reason: reason
      end

    commit_render_result(session, state.client_dom, result, event_view)
  end

  defp commit_key_default(session, locator, "Tab", _submission) do
    update_client_dom(session, &ClientDOM.press(&1, locator, "Tab"))
  end

  defp commit_key_default(session, _locator, "Enter", submission) do
    commit_implicit_enter(session, submission)
  end

  defp commit_key_default(session, _locator, _key, _submission), do: session

  defp commit_space_default(session, locator, "Space") do
    state = Session.page_state(session)
    {client_dom, target} = ClientDOM.click(state.client_dom, locator)

    if Semantics.input_type(target) in ["checkbox", "radio"],
      do: commit_checked(session, client_dom, target, locator),
      else: commit_click(session, client_dom, target)
  end

  defp commit_space_default(session, _locator, _key), do: session

  defp commit_implicit_enter(session, nil), do: session

  defp commit_implicit_enter(session, submission) do
    state = Session.page_state(session)

    form_target =
      state.client_dom
      |> ClientDOM.targets(Locator.new({:css, "form"}))
      |> Enum.find(&(&1.id == submission.form_id))

    event_context =
      case form_target do
        nil -> %{view: state.view, root_id: nil}
        target -> owning_view_context(state.view, target)
      end

    case submission do
      %{phx_submit?: true} ->
        dispatch_live_submit(session, state.client_dom, submission, event_context)

      %{phx_submit?: false} ->
        {:navigate, session, Navigation.submission(submission)}
    end
  end

  @impl true
  def unwrap(%Session{} = session, fun) when is_function(fun, 1) do
    state = Session.page_state(session)
    _ignored = fun.(state.view)
    reconcile_unwrapped(session, state.client_dom)
  end

  defp evaluate_expectation(%Session{} = session, %Expect{target: {:locator, locator}, kind: :count, expected: expected}) do
    candidates = session |> document() |> StaticLocator.resolve(locator)
    {:ok, length(candidates) == expected, length(candidates)}
  end

  defp evaluate_expectation(%Session{} = session, %Expect{target: {:locator, locator}, kind: :visible}) do
    document = document(session)
    candidates = StaticLocator.resolve(document, locator)
    visible_count = Enum.count(candidates, &structurally_visible?/1)
    actual = if visible_count > 0, do: visible_count, else: normalize(LazyHTML.text(document))
    {:ok, visible_count > 0, actual}
  end

  defp evaluate_expectation(%Session{} = session, %Expect{target: {:locator, locator}, kind: :disabled}) do
    actual = session |> client_dom() |> ClientDOM.disabled?(locator)
    {:ok, actual, actual}
  end

  defp evaluate_expectation(%Session{} = session, %Expect{target: {:locator, locator}, kind: :editable}) do
    actual = session |> client_dom() |> ClientDOM.editable?(locator)
    {:ok, actual, actual}
  end

  defp evaluate_expectation(%Session{} = session, %Expect{target: {:locator, locator}, kind: :enabled}) do
    actual = not (session |> client_dom() |> ClientDOM.disabled?(locator))
    {:ok, actual, actual}
  end

  defp evaluate_expectation(%Session{} = session, %Expect{target: {:locator, locator}, kind: :focused}) do
    actual = session |> client_dom() |> ClientDOM.focused?(locator)
    {:ok, actual, actual}
  end

  defp evaluate_expectation(%Session{}, %Expect{target: {:locator, _locator}, kind: :checked, expected: :indeterminate}) do
    raise Fluffy.CapabilityError,
      capability: :indeterminate_checked_state,
      driver: :live,
      detail: "indeterminate is a browser-owned DOM property"
  end

  defp evaluate_expectation(%Session{} = session, %Expect{target: {:locator, locator}, kind: :checked, expected: expected}) do
    actual = session |> client_dom() |> ClientDOM.checked?(locator)
    {:ok, actual == (expected == :checked), actual}
  end

  defp evaluate_expectation(%Session{} = session, %Expect{target: {:locator, locator}, kind: :value, expected: expected}) do
    actual = session |> client_dom() |> ClientDOM.value(locator)
    {:ok, actual == expected, actual}
  end

  defp evaluate_expectation(%Session{} = session, %Expect{target: {:locator, locator}, kind: :values, expected: expected}) do
    actual = session |> client_dom() |> ClientDOM.selected_values(locator)
    {:ok, actual == expected, actual}
  end

  defp evaluate_expectation(%Session{} = session, %Expect{target: :page, kind: :url, expected: expected}) do
    actual = Session.current_page(session).url
    {:ok, URLMatcher.matches?(expected, actual), actual}
  end

  defp evaluate_expectation(%Session{} = session, %Expect{target: :page, kind: :title, expected: expected}) do
    actual = session |> Session.page_state() |> Map.fetch!(:view) |> page_title()
    {:ok, Expect.title_matches?(expected, actual), actual}
  end

  defp client_dom(session), do: session |> Session.page_state() |> Map.fetch!(:client_dom)
  defp document(session), do: session |> client_dom() |> Map.fetch!(:document)

  defp structurally_visible?(element) do
    attributes =
      case LazyHTML.attributes(element) do
        [attributes] -> attributes
        _other -> []
      end

    not List.keymember?(attributes, "hidden", 0) and
      String.downcase(attribute(attributes, "aria-hidden") || "false") != "true"
  end

  defp resolve_live_action(session, locator, options, action) do
    options = Keyword.validate!(options, [:timeout])

    case Retry.run_current(
           session,
           options,
           &ActionResolver.attempt(&1, locator, action),
           &refresh/1,
           &wait_for_retry/2
         ) do
      {%Session{} = session, value} -> {session, value}
      navigation -> navigation
    end
  end

  defp eventually(session, options, attempt) do
    Retry.run(session, options, attempt, &refresh/1, &wait_for_retry/2)
  end

  defp refresh(session) do
    state = Session.page_state(session)

    try do
      case render(state.view) do
        html when is_binary(html) ->
          Session.put_page_state(session, %{
            state
            | client_dom: ClientDOM.reconcile(state.client_dom, html)
          })

        {:error, redirect} ->
          follow_redirect_result(session, {:error, redirect})
      end
    catch
      :exit, original_reason ->
        case live_view_exit_event(state.view, state.watcher, session.context.timeout) do
          {:redirect, redirect} -> follow_redirect_result(session, {:error, redirect})
          {:died, reason} -> raise Fluffy.LiveViewError, reason: reason
          :none -> raise Fluffy.LiveViewError, reason: original_reason
        end
    end
  end

  defp reconcile_unwrapped(session, client_dom) do
    state = Session.page_state(session)

    case current_redirect(state.view) do
      {:error, {_kind, _options}} = redirect ->
        follow_redirect_result(session, redirect)

      nil ->
        case live_view_event(state.watcher, 0) do
          {:redirect, redirect} ->
            follow_redirect_result(session, {:error, redirect})

          {:died, reason} ->
            raise Fluffy.LiveViewError, reason: reason

          :none ->
            try do
              state.view
              |> render()
              |> then(&commit_render_result(session, client_dom, &1))
            catch
              :exit, reason ->
                reconcile_unwrapped_exit(session, state.view, state.watcher, reason)
            end
        end
    end
  end

  defp reconcile_unwrapped_exit(session, view, watcher, original_reason) do
    case live_view_exit_event(view, watcher, session.context.timeout) do
      {:redirect, redirect} -> follow_redirect_result(session, {:error, redirect})
      {:died, reason} -> raise Fluffy.LiveViewError, reason: reason
      :none -> exit(original_reason)
    end
  end

  defp live_view_exit_event(view, watcher, timeout) do
    case current_redirect(view) do
      {:error, redirect} -> {:redirect, redirect}
      nil -> live_view_event(watcher, min(timeout, @retry_interval))
    end
  end

  defp live_view_event(watcher, wait) do
    receive do
      {:fluffy_live_view, ^watcher, event} -> event
    after
      wait -> :none
    end
  end

  defp wait_for_retry(session, wait) do
    state = Session.page_state(session)
    %{proxy: {reference, topic, _proxy_pid}} = state.view
    watcher = state.watcher

    receive do
      {^reference, {:patch, ^topic, %{to: destination}}} ->
        {:navigate, session, Navigation.patch(destination, state)}

      {:fluffy_live_view, ^watcher, {:died, reason}} ->
        raise Fluffy.LiveViewError, reason: reason

      {:fluffy_live_view, ^watcher, {:redirect, redirect}} ->
        follow_redirect_result(session, {:error, redirect})
    after
      wait -> session
    end
  end

  defp live_click_action(target) do
    cond do
      attribute(target.attributes, "data-phx-link") != nil ->
        :render_click

      is_nil(attribute(target.attributes, "phx-click")) ->
        :none

      true ->
        phx_click_action(attribute(target.attributes, "phx-click"))
    end
  end

  defp phx_click_action("[" <> _ = encoded) do
    commands = Phoenix.json_library().decode!(encoded)

    cond do
      Enum.any?(commands, &match?([command, _] when command in ["navigate", "patch", "push"], &1)) ->
        :render_click

      Enum.any?(commands, &match?(["dispatch", %{"event" => "change"}], &1)) ->
        :dispatch_change

      true ->
        :none
    end
  end

  defp phx_click_action(_event), do: :render_click

  defp attribute(attributes, name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp commit_render_result(session, client_dom, result, event_view \\ nil)

  defp commit_render_result(session, _client_dom, {:error, {_kind, _options}} = redirect, _event_view) do
    follow_redirect_result(session, redirect)
  end

  defp commit_render_result(session, client_dom, result, _event_view) when is_binary(result) do
    state = Session.page_state(session)

    rendered =
      try do
        {:ok, render(state.view)}
      catch
        :exit, reason -> {:exit, reason}
      end

    case rendered do
      {:ok, html} when is_binary(html) ->
        state = %{state | client_dom: ClientDOM.reconcile(client_dom, html)}
        session = session |> Session.put_page_state(state) |> prune_stale_live_uploads()

        case ClientDOM.triggered_submission(state.client_dom) do
          nil ->
            case current_patch(state.view) do
              nil -> session
              path -> {:navigate, session, Navigation.patch(path, state)}
            end

          submission ->
            {:navigate, session, Navigation.submission(submission)}
        end

      {:ok, {:error, redirect}} ->
        follow_redirect_result(session, {:error, redirect})

      {:exit, original_reason} ->
        case live_view_exit_event(state.view, state.watcher, session.context.timeout) do
          {:redirect, redirect} -> follow_redirect_result(session, {:error, redirect})
          {:died, reason} -> raise Fluffy.LiveViewError, reason: reason
          :none -> raise Fluffy.LiveViewError, reason: original_reason
        end
    end
  end

  defp follow_redirect_result(session, {:error, {_kind, %{to: destination} = options}}) do
    {:navigate, session, Navigation.redirect(destination, flash: options[:flash])}
  end

  defp current_patch(view) do
    %{proxy: {reference, topic, _}} = view

    receive do
      {^reference, {:patch, ^topic, %{to: destination}}} -> destination
    after
      0 -> nil
    end
  end

  defp current_redirect(view) do
    %{proxy: {reference, topic, _}} = view

    receive do
      {^reference, {:redirect, ^topic, %{to: _destination} = options}} ->
        {:error, {:redirect, options}}
    after
      0 -> nil
    end
  end

  defp dispatch_live_change(session, client_dom, %Locator{} = locator) do
    target = ClientDOM.target!(client_dom, locator)
    dispatch_live_change(session, client_dom, target)
  end

  defp dispatch_live_change(session, client_dom, %Fluffy.HTML.Target{} = target) do
    state = Session.page_state(session)
    event_context = owning_view_context(state.view, target)
    event_view = event_context.view
    session = Session.put_page_state(session, %{state | client_dom: client_dom})

    case ClientDOM.change_event(client_dom, target) do
      nil ->
        session

      event ->
        payload =
          event.fields
          |> Form.to_params()
          |> Map.put("_target", event.target_name || "undefined")
          |> decode_merge_target()

        result =
          try do
            event_view
            |> element(selector_for_view(client_dom, event.dispatcher_selector, event_context))
            |> render_change(payload)
          catch
            :exit, reason -> raise Fluffy.LiveViewError, reason: reason
          end

        commit_render_result(session, client_dom, result, event_view)
    end
  end

  defp dispatch_live_submit(session, client_dom, submission, event_context) do
    event_view = event_context.view

    form_selector =
      selector_for_view(
        client_dom,
        ClientDOM.selector_for_node_id(client_dom, submission.form_id),
        event_context
      )

    payload = Form.to_params(submission.fields)

    result =
      try do
        event_view
        |> element(form_selector)
        |> render_submit(payload)
      catch
        :exit, reason -> raise Fluffy.LiveViewError, reason: reason
      end

    commit_render_result(session, client_dom, result, event_view)
  end

  defp owning_view_context(root_view, target) do
    target.ancestors
    |> Kernel.++([target])
    |> Enum.reduce(%{view: root_view, root_id: nil}, fn candidate, context ->
      case {attribute(candidate.attributes, "data-phx-session"), attribute(candidate.attributes, "id")} do
        {session, id} when is_binary(session) and session != "" and is_binary(id) and id != "" ->
          if id == context.view.id do
            context
          else
            view =
              find_live_child(context.view, id) ||
                raise Fluffy.LiveViewError,
                  reason: {:nested_live_view_not_found, id, context.view.id}

            %{view: view, root_id: candidate.id}
          end

        _not_a_live_root ->
          context
      end
    end)
  end

  defp selector_for_view(_client_dom, selector, %{root_id: nil}), do: selector

  defp selector_for_view(client_dom, selector, %{root_id: root_id}) do
    root_selector = ClientDOM.selector_for_node_id(client_dom, root_id)

    case String.replace_prefix(selector, root_selector <> " > ", "") do
      ^selector ->
        raise Fluffy.LiveViewError,
          reason: {:target_outside_nested_live_view, selector, root_selector}

      relative_selector ->
        relative_selector
    end
  end

  defp set_live_upload(session, locator, selected_files) do
    state = Session.page_state(session)

    if !ClientDOM.live_change_form?(state.client_dom, locator) do
      raise Fluffy.CapabilityError,
        capability: :file_uploads,
        driver: :live,
        detail: "LiveView-managed file uploads require a phx-change form"
    end

    target = ClientDOM.target!(state.client_dom, locator)
    event_context = owning_view_context(state.view, target)
    form_id = Form.owner_id(state.client_dom.index, target)

    form_selector =
      selector_for_view(
        state.client_dom,
        ClientDOM.selector_for_node_id(state.client_dom, form_id),
        event_context
      )

    upload_name = existing_upload_name!(target)
    auto_upload? = live_auto_upload?(target)
    append? = live_multiple_file_input?(target) and live_upload_present?(session, form_id)
    client_dom = ClientDOM.set_input_files(state.client_dom, locator, selected_files)

    upload =
      UploadCompat.file_input!(
        event_context.view,
        form_selector,
        upload_name,
        Enum.map(selected_files, fn selected_file ->
          %{
            content: selected_file.bytes,
            last_modified: nil,
            name: selected_file.name,
            size: selected_file.size,
            type: selected_file.content_type
          }
        end),
        session.context.http.endpoint
      )

    session = if append?, do: session, else: release_live_upload_for_form(session, form_id)

    :ok =
      TestScope.register_upload_client(
        session.context.resource_scope,
        session.context.resource_id,
        upload.pid
      )

    # The selection-triggered `phx-change` may replace or remove this input.
    # Register its client state before reconciling that render, so stale-input
    # cleanup can release the upload rather than leaving an unreachable ref.
    session =
      put_live_upload(
        session,
        client_dom,
        form_id,
        target,
        upload,
        selected_files,
        false,
        append?
      )

    result =
      try do
        event_context.view
        |> element(form_selector)
        |> render_change(upload)
      catch
        :exit, reason -> raise Fluffy.LiveViewError, reason: reason
      end

    case commit_render_result(session, client_dom, result, event_context.view) do
      %Session{} = session when auto_upload? ->
        if live_upload_present?(session, form_id) do
          case dispatch_live_upload(
                 session,
                 upload,
                 upload_entry_names(upload),
                 event_context
               ) do
            {:ok, session} -> mark_live_upload_uploaded(session, form_id, upload.pid)
            {:entry_error, session} -> session
            {:navigation, navigation} -> navigation
          end
        else
          session
        end

      %Session{} = session ->
        session

      navigation ->
        navigation
    end
  end

  defp put_live_upload(session, client_dom, form_id, target, upload, selected_files, uploaded?, append?) do
    state = Session.page_state(session)

    live_uploads =
      UploadState.put(
        state.live_uploads,
        form_id,
        ClientDOM.target_identity(target),
        target.selector,
        upload,
        selected_files,
        uploaded: uploaded?,
        append: append?
      )

    state
    |> Map.put(:client_dom, client_dom)
    |> Map.put(:live_uploads, live_uploads)
    |> then(&Session.put_page_state(session, &1))
  end

  defp live_upload_present?(session, form_id) do
    session |> Session.page_state() |> Map.fetch!(:live_uploads) |> UploadState.present?(form_id)
  end

  defp mark_live_upload_uploaded(session, form_id, upload_pid) do
    state = Session.page_state(session)

    state = %{
      state
      | live_uploads: UploadState.mark_uploaded(state.live_uploads, form_id, upload_pid)
    }

    Session.put_page_state(session, state)
  end

  defp live_auto_upload?(target) do
    attribute(target.attributes, "data-phx-auto-upload") not in [nil, false, "false"]
  end

  defp live_multiple_file_input?(target) do
    attribute(target.attributes, "multiple") not in [nil, false, "false"]
  end

  defp existing_upload_name!(target) do
    case attribute(target.attributes, "name") do
      name when is_binary(name) and name != "" ->
        case existing_atom(name) do
          {:ok, atom} ->
            atom

          :error ->
            raise Fluffy.CapabilityError,
              capability: :file_uploads,
              driver: :live,
              detail: "LiveView-managed file uploads require the input name to be an existing upload atom"
        end

      _missing_name ->
        raise Fluffy.CapabilityError,
          capability: :file_uploads,
          driver: :live,
          detail: "LiveView-managed file uploads require a named file input"
    end
  end

  defp existing_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> :error
  end

  defp live_upload_for_submit(session, target) do
    state = Session.page_state(session)

    case Form.owner_id(state.client_dom.index, target) do
      nil ->
        :none

      form_id ->
        case UploadState.get(state.live_uploads, form_id) do
          nil -> :none
          upload_state -> {:ok, form_id, upload_state}
        end
    end
  end

  defp release_live_upload_for_form(session, form_id) do
    state = Session.page_state(session)

    case UploadState.fetch(state.live_uploads, form_id) do
      {:ok, upload_state} ->
        release_live_upload_clients(session, upload_state)
        {_form, live_uploads} = UploadState.delete_form(state.live_uploads, form_id)
        Session.put_page_state(session, %{state | live_uploads: live_uploads})

      :error ->
        session
    end
  end

  # A LiveView cancel control carries the selected entry's `phx-value-ref`.
  # Once its event removes that entry from the rendered page, the test upload
  # client is unreachable and must be released before a later submit can try
  # to transfer the cancelled bytes.
  defp release_cancelled_live_upload(session, target) do
    entry_ref = attribute(target.attributes, "phx-value-ref")
    state = Session.page_state(session)

    case find_live_upload_entry(state, entry_ref) do
      {form_id, upload_state, entry_upload} when is_binary(entry_ref) ->
        release_missing_live_upload_entry(
          session,
          state.client_dom,
          form_id,
          upload_state,
          entry_upload,
          entry_ref
        )

      _no_matching_entry ->
        session
    end
  end

  defp release_missing_live_upload_entry(session, client_dom, form_id, upload_state, entry_upload, entry_ref) do
    if live_upload_entry_rendered?(client_dom, entry_ref) do
      session
    else
      remaining_entries = Enum.reject(entry_upload.entries, &(&1.ref == entry_ref))
      sync_cancelled_live_upload(session, form_id, upload_state, entry_upload, remaining_entries)
    end
  end

  defp sync_cancelled_live_upload(session, form_id, upload_state, entry_upload, []) do
    session = release_live_upload_client(session, entry_upload.upload)
    session = remove_live_upload(session, form_id, entry_upload.upload.pid)

    selected_files =
      case UploadState.get(Session.page_state(session).live_uploads, form_id) do
        nil -> []
        form -> UploadState.selected_files(form.batches)
      end

    put_live_upload_files(session, upload_state, selected_files)
  end

  defp sync_cancelled_live_upload(session, form_id, upload_state, entry_upload, remaining_entries) do
    session
    |> put_live_upload_files(upload_state, Enum.map(remaining_entries, & &1.selected_file))
    |> put_live_upload_entries(form_id, entry_upload.upload.pid, remaining_entries)
  end

  defp live_upload_entry_rendered?(client_dom, entry_ref) do
    selector = ~s([phx-value-ref="#{entry_ref}"])
    StaticLocator.resolve(client_dom.document, Locator.new({:css, selector})) != []
  end

  defp put_live_upload_files(session, %{input_selector: selector}, selected_files) do
    state = Session.page_state(session)
    locator = Locator.new({:css, selector})
    client_dom = ClientDOM.set_input_files(state.client_dom, locator, selected_files)
    Session.put_page_state(session, %{state | client_dom: client_dom})
  end

  defp put_live_upload_entries(session, form_id, upload_pid, entries) do
    state = Session.page_state(session)
    live_uploads = UploadState.put_entries(state.live_uploads, form_id, upload_pid, entries)
    Session.put_page_state(session, %{state | live_uploads: live_uploads})
  end

  defp dispatch_live_upload_submit(session, _client_dom, form_id, upload_state, submission, event_context) do
    upload_result =
      Enum.reduce_while(upload_state.batches, {:ok, session}, fn entry_upload, {:ok, session} ->
        case entry_upload do
          %{uploaded?: true} ->
            {:cont, {:ok, session}}

          %{entries: entries, upload: upload} ->
            case dispatch_live_upload(session, upload, entry_names(entries), event_context) do
              {:ok, session} -> {:cont, {:ok, session}}
              {:entry_error, session} -> {:halt, {:entry_error, session}}
              {:navigation, navigation} -> {:halt, {:navigation, navigation}}
            end
        end
      end)

    case upload_result do
      {:ok, session} ->
        dispatch_live_upload_submit_event(session, form_id, submission, event_context)

      {:entry_error, session} ->
        session

      {:navigation, navigation} ->
        navigation
    end
  end

  defp dispatch_live_upload_submit_event(session, form_id, submission, event_context) do
    state = Session.page_state(session)

    form_selector =
      selector_for_view(
        state.client_dom,
        ClientDOM.selector_for_node_id(state.client_dom, form_id),
        event_context
      )

    payload = Form.to_params(submission.fields)

    submit_result =
      try do
        event_context.view
        |> element(form_selector)
        |> render_submit(payload)
      catch
        :exit, reason -> raise Fluffy.LiveViewError, reason: reason
      end

    case commit_render_result(session, state.client_dom, submit_result, event_context.view) do
      %Session{} = session ->
        release_live_upload_for_form(session, form_id)

      {:navigate, %Session{} = session, navigation} ->
        {:navigate, release_live_upload_for_form(session, form_id), navigation}
    end
  end

  defp find_live_upload_entry(state, entry_ref) when is_binary(entry_ref) do
    UploadState.find_entry(state.live_uploads, entry_ref)
  end

  defp find_live_upload_entry(_state, _entry_ref), do: nil

  defp remove_live_upload(session, form_id, upload_pid) do
    state = Session.page_state(session)
    live_uploads = UploadState.remove_batch(state.live_uploads, form_id, upload_pid)
    Session.put_page_state(session, %{state | live_uploads: live_uploads})
  end

  defp release_live_upload_clients(session, %{batches: batches}) do
    Enum.each(batches, &release_live_upload_client(session, &1.upload))
  end

  defp release_live_upload_client(session, upload) do
    release_upload_client(session, upload)
    session
  end

  defp dispatch_live_upload(session, upload, entry_names, event_context) do
    Enum.reduce_while(entry_names, {:ok, session}, fn entry_name, {:ok, session} ->
      upload_result =
        try do
          render_upload(upload, entry_name)
        catch
          :exit, reason -> raise Fluffy.LiveViewError, reason: reason
        end

      case upload_result do
        {:error, _entry_errors} ->
          {:halt, {:entry_error, session}}

        _result ->
          state = Session.page_state(session)

          case commit_render_result(
                 session,
                 state.client_dom,
                 upload_result,
                 event_context.view
               ) do
            %Session{} = session -> {:cont, {:ok, session}}
            navigation -> {:halt, {:navigation, navigation}}
          end
      end
    end)
  end

  defp upload_entry_names(upload), do: Enum.map(upload.entries, &Map.fetch!(&1, "name"))
  defp entry_names(entries), do: Enum.map(entries, & &1.name)

  defp prune_stale_live_uploads(%Session{} = session) do
    state = Session.page_state(session)

    {live_uploads, stale_uploads} =
      UploadState.prune(state.live_uploads, fn upload_state ->
        ClientDOM.target_identity_present?(state.client_dom, upload_state.input_identity)
      end)

    Enum.each(stale_uploads, &release_live_upload_clients(session, &1))

    Session.put_page_state(session, %{state | live_uploads: live_uploads})
  end

  defp release_upload_client(session, upload) do
    TestScope.release_upload_client(
      session.context.resource_scope,
      session.context.resource_id,
      upload.pid
    )

    UploadCompat.stop(upload)
  end

  # Keep this in step with Phoenix.LiveView.Channel's `_target` decoding. The
  # browser sends the input name as a string; the channel query-decodes that
  # name and walks the resulting single keyspace to produce the target path.
  defp decode_merge_target(%{"_target" => target} = params) when is_list(target), do: params

  defp decode_merge_target(%{"_target" => target} = params) when is_binary(target) do
    keyspace = target |> Plug.Conn.Query.decode() |> gather_keys([])
    Map.put(params, "_target", Enum.reverse(keyspace))
  end

  defp decode_merge_target(%{} = params), do: params

  defp gather_keys(%{} = map, acc) do
    case :maps.next(:maps.iterator(map)) do
      {key, value, _iterator} -> gather_keys(value, [key | acc])
      :none -> acc
    end
  end

  defp gather_keys([], acc), do: acc
  defp gather_keys([%{} = map], acc), do: gather_keys(map, acc)
  defp gather_keys(_value, acc), do: acc

  defp update_client_dom(session, fun) do
    state = Session.page_state(session)
    Session.put_page_state(session, %{state | client_dom: fun.(state.client_dom)})
  end

  defp normalize(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
