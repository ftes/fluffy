defmodule Fluffy.Backend.Playwright do
  @moduledoc false

  @behaviour Fluffy.Backend.Contract

  alias Fluffy.Backend.Playwright.Context
  alias Fluffy.BrowserRuntime
  alias Fluffy.Dialog, as: DialogResult
  alias Fluffy.Download
  alias Fluffy.Driver.Playwright.State
  alias Fluffy.FailureArtifact
  alias Fluffy.FileChooser
  alias Fluffy.HTTPEvent
  alias Fluffy.Navigation.BrowserCommitted
  alias Fluffy.Navigation.BrowserPatch
  alias Fluffy.NavigationEvent
  alias Fluffy.Page
  alias Fluffy.PageLifecycle
  alias Fluffy.Playwright.NavigationObserver
  alias Fluffy.PlaywrightEventListener
  alias Fluffy.Session
  alias Fluffy.TestScope
  alias PlaywrightEx.Artifact
  alias PlaywrightEx.Browser
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Connection
  alias PlaywrightEx.Dialog, as: BrowserDialog
  alias PlaywrightEx.Frame
  alias PlaywrightEx.Page, as: BrowserPage
  alias PlaywrightEx.Tracing

  @impl true
  def start_session(options, attachment) do
    {resource_scope, resource_id, sandbox_header} = TestScope.attachment_values(attachment)
    browser_id = BrowserRuntime.browser_id()
    %{playwright_supervisor: playwright_supervisor} = BrowserRuntime.status()
    connection = PlaywrightEx.Supervisor.connection_name(playwright_supervisor)

    browser_context_options = Keyword.get(options, :browser_context, [])

    browser_context_headers =
      browser_context_options
      |> Keyword.get(:extra_http_headers, %{})
      |> Map.to_list()

    headers =
      (browser_context_headers ++ Keyword.get(options, :headers, []))
      |> deduplicate_headers()
      |> put_header(sandbox_header)
      |> Enum.map(fn {name, value} -> %{name: to_string(name), value: to_string(value)} end)

    base_url = Keyword.fetch!(options, :base_url)

    context_options =
      browser_context_options
      |> Keyword.delete(:extra_http_headers)
      |> normalize_browser_context_options()
      |> Keyword.put_new(:locale, "en")
      |> Keyword.put(:base_url, base_url)
      # playwright_ex 0.8 does not special-case this protocol acronym when
      # camelizing `:extra_http_headers`, so use the exact wire key.
      |> Keyword.put(:extraHTTPHeaders, headers)
      |> Keyword.put(:connection, connection)
      |> Keyword.put(:timeout, timeout())

    {:ok, context} =
      Browser.new_context(browser_id, context_options)

    :ok = TestScope.register_browser_context(resource_scope, resource_id, context.guid)

    {:ok, browser_page} =
      BrowserContext.new_page(context.guid, connection: connection, timeout: timeout())

    subscribe_to_console!(browser_page.guid, connection)

    context_state = %Context{
      connection: connection,
      context_id: context.guid,
      tracing_id: context.tracing.guid,
      base_url: base_url,
      resource_id: resource_id,
      resource_scope: resource_scope,
      timeout: Keyword.get(options, :timeout, timeout())
    }

    page_state =
      new_page_state(
        context.guid,
        browser_page.guid,
        browser_page.main_frame.guid
      )

    page = %Page{id: :main, driver: :playwright, state: page_state}

    Session.new(__MODULE__, context_state, page)
  end

  @impl true
  def close_session(%Session{} = session) do
    Enum.each(session.pages, fn {_name, page} -> stop_navigation_observer(session, page.state) end)

    case TestScope.close_session(session.context.resource_scope, session.context.resource_id) do
      :ok ->
        :ok

      :not_managed ->
        case BrowserContext.close(session.context.context_id, timeout: timeout()) do
          {:ok, _result} -> :ok
          {:error, error} -> {:error, error}
        end
    end
  end

  @impl true
  def run_step(%Session{context: %{trace: trace}} = session, name, location, fun) when not is_nil(trace) do
    Tracing.group(
      session.context.tracing_id,
      [
        connection: session.context.connection,
        timeout: session.context.timeout,
        name: name,
        location: location
      ],
      fun
    )
  end

  def run_step(%Session{}, _name, _location, fun), do: fun.()

  @impl true
  def capture_failure(%Session{} = session, operation, error, stacktrace) do
    FailureArtifact.capture(session, operation, error, stacktrace)
  end

  @impl true
  def absolute_url(%Session{} = session, path) do
    session.context.base_url |> URI.merge(path) |> URI.to_string()
  end

  @impl true
  def visit(%Session{backend: __MODULE__} = session, path) do
    state = Session.page_state(session)
    navigation_timeout = session.context.timeout

    case Frame.goto(state.frame_id,
           url: path,
           wait_until: "load",
           timeout: navigation_timeout
         ) do
      {:ok, response} ->
        adopt_navigated_document(
          session,
          state,
          response_metadata(response),
          nil,
          navigation_timeout
        )

      {:error, error} ->
        raise "Playwright navigation failed: #{inspect(error)}"
    end
  end

  @impl true
  def reload(%Session{backend: __MODULE__} = session, options \\ []) do
    options = Keyword.validate!(options, [:timeout])
    state = Session.page_state(session)
    reload_timeout = options |> Keyword.get(:timeout, session.context.timeout) |> max(1)

    case BrowserPage.reload(state.page_id,
           connection: session.context.connection,
           timeout: reload_timeout
         ) do
      {:ok, response} ->
        adopt_navigated_document(session, state, response_metadata(response), nil, reload_timeout)

      {:error, error} ->
        raise "Playwright reload failed: #{inspect(error)}"
    end
  end

  @impl true
  def navigate(%Session{backend: __MODULE__} = session, %BrowserCommitted{
        state: state,
        url: url,
        response: response,
        live_navigation_cursor: live_navigation_cursor
      }) do
    navigation_timeout = session.context.timeout

    adopt_navigated_document(
      session,
      state,
      response,
      url,
      navigation_timeout,
      live_navigation_cursor
    )
  end

  def navigate(%Session{backend: __MODULE__} = session, %BrowserPatch{state: state, url: url}) do
    Session.commit_page(session, :playwright, state, url)
  end

  @impl true
  def activate_page(%Session{} = session, page_id) do
    page = fetch_page!(session, page_id)

    case BrowserPage.bring_to_front(page.state.page_id, timeout: session.context.timeout) do
      {:ok, _result} ->
        Session.activate_page(session, page_id)

      {:error, error} ->
        raise "Could not activate Playwright page #{inspect(page_id)}: #{inspect(error)}"
    end
  end

  @impl true
  def close_page(%Session{} = session, page_id) do
    PageLifecycle.close_page(session, page_id, &release_page/3)
  end

  @impl true
  def arm_event(%Session{} = session, :download, options) do
    {:ok, listener} =
      PlaywrightEventListener.start_link(
        guid: Session.page_state(session).page_id,
        filter: &match?(%{method: :download}, &1),
        timeout: Keyword.fetch!(options, :timeout)
      )

    {:ok, session, %{type: :download, listener: listener, options: options}}
  end

  def arm_event(%Session{} = session, :navigation, options) do
    state = Session.page_state(session)

    {:ok, navigation_listener} =
      PlaywrightEventListener.start_link(
        guid: state.frame_id,
        filter: fn
          %{method: :navigated, params: params} -> not is_binary(params[:error])
          _event -> false
        end,
        timeout: Keyword.fetch!(options, :timeout)
      )

    response_observer =
      NavigationObserver.arm(
        session.context.context_id,
        state.page_id,
        state.frame_id,
        Keyword.fetch!(options, :timeout)
      )

    {:ok, session,
     %{
       type: :navigation,
       navigation_listener: navigation_listener,
       response_observer: response_observer,
       from_url: Session.current_page(session).url,
       options: options
     }}
  end

  def arm_event(%Session{} = session, :page, options) do
    %{key: name} = Session.pending_event(session)

    if Map.has_key?(session.pages, name) do
      raise ArgumentError, "page name #{inspect(name)} is already in use"
    end

    {:ok, listener} =
      PlaywrightEventListener.start_link(
        guid: session.context.context_id,
        filter: &match?(%{method: :page}, &1),
        timeout: Keyword.fetch!(options, :timeout)
      )

    response_observer =
      NavigationObserver.arm_popup(
        session.context.context_id,
        Session.page_state(session).frame_id,
        Keyword.fetch!(options, :timeout)
      )

    {:ok, session,
     %{
       type: :page,
       listener: listener,
       response_observer: response_observer,
       name: name,
       opener: session.active_page,
       options: options
     }}
  end

  def arm_event(%Session{} = session, :dialog, options) do
    decision = Keyword.fetch!(options, :decision)
    event_timeout = Keyword.fetch!(options, :timeout)
    deadline = Keyword.fetch!(options, :deadline)

    {:ok, listener} =
      PlaywrightEventListener.start_link(
        guid: Session.page_state(session).page_id,
        filter: &match?(%{method: :__create__, params: %{type: "Dialog"}}, &1),
        handler: &handle_dialog(&1, decision, deadline),
        subscription: :dialog,
        timeout: event_timeout
      )

    {:ok, session, %{type: :dialog, listener: listener, options: options}}
  end

  def arm_event(%Session{} = session, :file_chooser, options) do
    {:ok, listener} =
      PlaywrightEventListener.start_link(
        guid: Session.page_state(session).page_id,
        filter: &match?(%{method: :file_chooser}, &1),
        handler: fn
          %{
            guid: page_id,
            params: %{element: %{guid: element_id}, is_multiple: multiple?}
          } ->
            {:ok,
             %FileChooser{
               element_id: element_id,
               page_id: page_id,
               multiple?: multiple?
             }}
        end,
        subscription: :file_chooser,
        timeout: Keyword.fetch!(options, :timeout)
      )

    {:ok, session, %{type: :file_chooser, listener: listener, options: options}}
  end

  def arm_event(%Session{} = session, type, options) when type in [:request, :response] do
    matcher = Keyword.fetch!(options, :matcher)

    {:ok, listener} =
      PlaywrightEventListener.start_link(
        guid: session.context.context_id,
        filter: &network_event_matches?(session, &1, type, matcher),
        handler: fn event -> {:ok, normalize_http_event(session, event, type)} end,
        subscription: type,
        timeout: Keyword.fetch!(options, :timeout)
      )

    {:ok, session, %{type: type, listener: listener, options: options}}
  end

  def arm_event(%Session{} = session, type, options) do
    {:ok, session, %{type: type, options: options}}
  end

  @impl true
  def await_event(%Session{} = session, %{type: :download} = resource, timeout) do
    case PlaywrightEventListener.await(resource.listener, timeout) do
      {:ok, event} -> {:ok, session, normalize_download(event, resource.options, timeout)}
      {:error, reason} -> {:error, reason}
    end
  end

  def await_event(%Session{} = session, %{type: :navigation} = resource, timeout) do
    case PlaywrightEventListener.await(resource.navigation_listener, timeout) do
      {:ok, navigation_event} ->
        finish_navigation_event(session, resource, navigation_event)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def await_event(%Session{} = session, %{type: :page} = resource, timeout) do
    deadline = Keyword.fetch!(resource.options, :deadline)

    case PlaywrightEventListener.await(resource.listener, timeout) do
      {:ok, %{params: %{page: %{guid: page_id}}}} ->
        initializer =
          Connection.initializer!(PlaywrightEx.Supervisor.Connection, page_id)

        subscribe_to_console!(page_id, session.context.connection, remaining(deadline))
        frame_id = initializer.main_frame.guid

        state = %State{
          context_id: session.context.context_id,
          page_id: page_id,
          frame_id: frame_id
        }

        url = current_url(state, remaining(deadline))

        response =
          if http_document?(url) do
            case Frame.wait_for_load_state(frame_id, state: "load", timeout: remaining(deadline)) do
              {:ok, _result} -> :ok
              {:error, error} -> raise "Captured Playwright page did not load: #{inspect(error)}"
            end

            await_popup_response!(resource.response_observer, frame_id, deadline)
          end

        {state, url} = ready_navigated_document(session, state, url, remaining(deadline))

        page = %Page{
          id: resource.name,
          driver: :playwright,
          state: state,
          opener: resource.opener
        }

        page = Page.commit(page, :playwright, state, url, status: response_status(response))
        session = Session.put_page(session, page)

        {:ok, session, page}

      {:ok, event} ->
        {:error, {:unexpected_page_event, event}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def await_event(%Session{} = session, %{type: :dialog} = resource, timeout) do
    case PlaywrightEventListener.await(resource.listener, timeout) do
      {:ok, dialog} -> {:ok, session, dialog}
      {:error, reason} -> {:error, reason}
    end
  end

  def await_event(%Session{} = session, %{type: :file_chooser} = resource, timeout) do
    case PlaywrightEventListener.await(resource.listener, timeout) do
      {:ok, chooser} -> {:ok, session, chooser}
      {:error, reason} -> {:error, reason}
    end
  end

  def await_event(%Session{} = session, %{type: type} = resource, timeout) when type in [:request, :response] do
    case PlaywrightEventListener.await(resource.listener, timeout) do
      {:ok, event} -> {:ok, session, event}
      {:error, reason} -> {:error, reason}
    end
  end

  def await_event(%Session{} = _session, _resource, _timeout), do: {:error, :timeout}

  @impl true
  def disarm_event(%{navigation_listener: navigation_listener, response_observer: response_observer}) do
    PlaywrightEventListener.stop(navigation_listener)
    NavigationObserver.stop(response_observer)
    :ok
  end

  def disarm_event(%{listener: listener, response_observer: response_observer}) do
    PlaywrightEventListener.stop(listener)
    NavigationObserver.stop(response_observer)
    :ok
  end

  def disarm_event(%{listener: listener}) do
    PlaywrightEventListener.stop(listener)
  end

  def disarm_event(_resource), do: :ok

  defp normalize_download(%{params: params}, options, timeout) do
    artifact_guid = params.artifact.guid
    filename = params.suggested_filename
    path = Path.join(System.tmp_dir!(), "fluffy-download-#{System.unique_integer([:positive])}")

    try do
      case Artifact.save_as(artifact_guid, path, timeout: max(timeout, 1)) do
        :ok -> :ok
        {:error, error} -> raise "Could not save Playwright download: #{inspect(error)}"
      end

      {:ok, stat} = File.stat(path)
      max_bytes = Keyword.fetch!(options, :max_bytes)

      if stat.size > max_bytes do
        raise ExUnit.AssertionError,
          message: "Downloaded #{stat.size} bytes, exceeding the configured :max_bytes limit of #{max_bytes}"
      end

      %Download{
        filename: filename,
        content_type: MIME.from_path(filename),
        bytes: File.read!(path),
        url: params.url
      }
    after
      _result = File.rm(path)
      _result = Artifact.delete(artifact_guid, timeout: max(timeout, 1))
    end
  end

  defp finish_navigation_event(session, resource, navigation_event) do
    if get_in(navigation_event, [:params, :new_document]) do
      timeout = remaining(Keyword.fetch!(resource.options, :deadline))

      case NavigationObserver.await(resource.response_observer, timeout) do
        {:ok, response} ->
          page = Session.current_page(session)
          session = Session.put_page_status(session, response.status)

          {:ok, session,
           %NavigationEvent{
             from_url: resource.from_url,
             url: page.url,
             status: response.status
           }}

        {:error, reason} ->
          {:error, reason}
      end
    else
      page = Session.current_page(session)

      {:ok, session,
       %NavigationEvent{
         from_url: resource.from_url,
         url: page.url,
         status: page.status
       }}
    end
  end

  defp await_popup_response!(observer, frame_id, deadline) do
    case NavigationObserver.await(observer, remaining(deadline)) do
      {:ok, %{frame_id: ^frame_id} = response} ->
        NavigationObserver.stop(observer)
        response

      {:ok, response} ->
        NavigationObserver.stop(observer)
        raise "Captured response for an unexpected popup page: #{inspect(response)}"

      {:error, reason} ->
        NavigationObserver.stop(observer)
        raise "Could not capture the popup main-document response: #{inspect(reason)}"
    end
  end

  defp release_page(session, page, :page_closed) do
    stop_navigation_observer(session, page.state)

    case BrowserPage.close(page.state.page_id, timeout: session.context.timeout) do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        raise "Could not close Playwright page #{inspect(page.id)}: #{inspect(error)}"
    end
  end

  defp fetch_page!(session, page_id) do
    case Map.fetch(session.pages, page_id) do
      {:ok, page} ->
        page

      :error ->
        raise ArgumentError, "no page named #{inspect(page_id)} exists in this session"
    end
  end

  defp handle_dialog(%{params: params}, decision, deadline) do
    dialog = normalize_dialog(params.initializer)
    decision = if is_function(decision, 1), do: decision.(dialog), else: decision
    {action, prompt_text} = normalize_dialog_decision!(decision)
    timeout = remaining(deadline)

    result =
      case action do
        :accept ->
          accept_options =
            then([timeout: max(timeout, 1)], fn options ->
              if prompt_text, do: Keyword.put(options, :prompt_text, prompt_text), else: options
            end)

          BrowserDialog.accept(params.guid, accept_options)

        :dismiss ->
          BrowserDialog.dismiss(params.guid, timeout: max(timeout, 1))
      end

    case result do
      {:ok, _result} -> {:ok, %{dialog | action: action, prompt_text: prompt_text}}
      {:error, error} -> {:error, {:dialog_handling_failed, error}}
    end
  end

  defp normalize_dialog(initializer) do
    %DialogResult{
      type: normalize_dialog_type(initializer.type),
      message: initializer.message,
      default_value: initializer.default_value || ""
    }
  end

  defp normalize_dialog_type(type) do
    case type do
      "alert" -> :alert
      "beforeunload" -> :beforeunload
      "confirm" -> :confirm
      "prompt" -> :prompt
      other -> other
    end
  end

  defp normalize_dialog_decision!(:accept), do: {:accept, nil}
  defp normalize_dialog_decision!(:dismiss), do: {:dismiss, nil}

  defp normalize_dialog_decision!({:accept, prompt_text}) when is_binary(prompt_text), do: {:accept, prompt_text}

  defp normalize_dialog_decision!(decision) do
    raise ArgumentError,
          "dialog decision callback returned invalid decision: #{inspect(decision)}"
  end

  defp network_event_matches?(session, %{method: type} = event, type, matcher) do
    session
    |> normalize_http_event(event, type)
    |> matches_network?(matcher, session.context.base_url)
  end

  defp network_event_matches?(_session, _event, _type, _matcher), do: false

  defp normalize_http_event(session, %{params: params}, :request) do
    request = initializer!(params.request.guid)

    %HTTPEvent{
      kind: :request,
      method: request.method,
      url: request.url,
      headers: normalize_headers(request.headers),
      resource_type: request.resource_type,
      post_data: decode_protocol_binary(request[:post_data]),
      page: page_name(session, params[:page])
    }
  end

  defp normalize_http_event(session, %{params: params}, :response) do
    response = initializer!(params.response.guid)
    request = initializer!(response.request.guid)

    %HTTPEvent{
      kind: :response,
      method: request.method,
      url: response.url,
      headers: normalize_headers(response.headers),
      resource_type: request.resource_type,
      post_data: decode_protocol_binary(request[:post_data]),
      status: response.status,
      status_text: response.status_text,
      page: page_name(session, params[:page])
    }
  end

  defp initializer!(guid) do
    Connection.initializer!(PlaywrightEx.Supervisor.Connection, guid)
  end

  defp normalize_headers(headers) do
    Map.new(headers, fn %{name: name, value: value} -> {String.downcase(name), value} end)
  end

  defp decode_protocol_binary(nil), do: nil

  defp decode_protocol_binary(value) do
    case Base.decode64(value) do
      {:ok, decoded} -> decoded
      :error -> value
    end
  end

  defp page_name(_session, nil), do: nil

  defp page_name(session, %{guid: page_id}) do
    Enum.find_value(session.pages, fn {name, page} ->
      if page.state.page_id == page_id, do: name
    end)
  end

  defp matches_network?(event, matcher, _base_url) when is_function(matcher, 1), do: matcher.(event)

  defp matches_network?(event, %Regex{} = matcher, _base_url), do: Regex.match?(matcher, event.url)

  defp matches_network?(event, matcher, base_url) when is_binary(matcher) do
    expected = base_url |> URI.merge(matcher) |> URI.to_string()
    event.url == expected
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 1)

  defp current_url(state, timeout) do
    case Frame.evaluate(state.frame_id,
           expression: "() => location.href",
           is_function: true,
           timeout: timeout
         ) do
      {:ok, path} -> path
      {:error, error} -> raise "Could not read the current browser URL: #{inspect(error)}"
    end
  end

  defp response_metadata(%{response: %{guid: guid}}) do
    Connection.initializer!(PlaywrightEx.Supervisor.Connection, guid)
  end

  defp response_metadata(_no_response), do: nil

  defp adopt_navigated_document(session, state, response, url, timeout, live_navigation_cursor \\ nil) do
    {state, url} =
      ready_navigated_document(session, state, url, timeout, live_navigation_cursor)

    metadata =
      case response_status(response) do
        nil -> []
        status -> [status: status]
      end

    Session.commit_page(session, :playwright, state, url, metadata)
  end

  defp ready_navigated_document(session, state, url, timeout, live_navigation_cursor \\ nil) do
    deadline = System.monotonic_time(:millisecond) + timeout
    destination = url || current_url(state, remaining(deadline))
    wait_for_live_view(state, destination, remaining(deadline), live_navigation_cursor)

    state =
      state
      |> Map.put(:document_identity, document_identity(state, remaining(deadline)))
      |> tap(&install_live_navigation_listener(&1, destination, remaining(deadline)))
      |> refresh_navigation_observer(session, remaining(deadline))

    {state, destination}
  end

  defp response_status(%{status: status}), do: status
  defp response_status(_no_response), do: nil

  defp http_document?(url) do
    URI.parse(url).scheme in ["http", "https"]
  end

  defp new_page_state(context_id, page_id, frame_id) do
    %State{
      context_id: context_id,
      frame_id: frame_id,
      page_id: page_id
    }
  end

  defp refresh_navigation_observer(state, session, timeout) do
    stop_navigation_observer(session, state)

    observer =
      NavigationObserver.arm(
        state.context_id,
        state.page_id,
        state.frame_id,
        timeout
      )

    :ok =
      TestScope.register_navigation_observer(
        session.context.resource_scope,
        session.context.resource_id,
        observer
      )

    %{state | navigation_observer: observer}
  end

  defp stop_navigation_observer(_session, %{navigation_observer: nil}), do: :ok

  defp stop_navigation_observer(session, %{navigation_observer: observer}) do
    NavigationObserver.stop(observer)

    TestScope.release_navigation_observer(
      session.context.resource_scope,
      session.context.resource_id,
      observer
    )
  end

  defp wait_for_live_view(state, destination, timeout, live_navigation_cursor) do
    deadline = System.monotonic_time(:millisecond) + timeout

    wait_for_live_navigation_completion(
      state,
      destination,
      live_navigation_cursor,
      remaining(deadline)
    )

    case Frame.evaluate(state.frame_id,
           expression: "() => document.querySelector('[data-phx-main]') !== null",
           is_function: true,
           timeout: remaining(deadline)
         ) do
      {:ok, true} ->
        result =
          Frame.wait_for_selector(state.frame_id,
            selector: "css=[data-phx-main].phx-connected",
            state: "attached",
            strict: true,
            timeout: remaining(deadline)
          )

        case result do
          {:ok, _element} ->
            :ok

          {:error, error} ->
            raise "LiveView browser connection failed for #{navigation_target(state, destination)}: expected [data-phx-main].phx-connected, got #{inspect(error)}"
        end

      {:ok, false} ->
        :ok

      {:error, error} ->
        raise "Could not inspect #{navigation_target(state, destination)} for [data-phx-main].phx-connected: #{inspect(error)}"
    end
  end

  defp install_live_navigation_listener(state, destination, timeout) do
    case Frame.evaluate(state.frame_id,
           expression: """
           () => {
             const eventKey = '__fluffyLiveNavigationEvents'

             if (!Array.isArray(window[eventKey])) {
               window[eventKey] = []
               window.addEventListener('phx:page-loading-start', event => {
                 const {kind, to} = event.detail ?? {}

                 if (kind === 'patch' || kind === 'redirect') {
                   window[eventKey].push({kind, to, complete: false})
                 }
               })
               window.addEventListener('phx:page-loading-stop', event => {
                 const {kind, to} = event.detail ?? {}
                 const pending = [...window[eventKey]].reverse().find(candidate =>
                   !candidate.complete && candidate.kind === kind && candidate.to === to
                 )

                 if (pending) pending.complete = true
               })
             }

             return true
           }
           """,
           is_function: true,
           timeout: timeout
         ) do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        raise "Could not install the LiveView navigation observer for #{navigation_target(state, destination)}: #{inspect(error)}"
    end
  end

  defp wait_for_live_navigation_completion(_state, _destination, nil, _timeout), do: :ok

  defp wait_for_live_navigation_completion(state, destination, cursor, timeout) do
    case Frame.wait_for_function(state.frame_id,
           expression: """
           cursor => window.__fluffyLiveNavigationEvents
             ?.slice(cursor)
             .some(event => event.kind === 'redirect' && event.complete)
           """,
           is_function: true,
           arg: cursor,
           timeout: timeout
         ) do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        raise "LiveView browser navigation failed for #{navigation_target(state, destination)}: expected redirect completion before [data-phx-main].phx-connected, got #{inspect(error)}"
    end
  end

  defp document_identity(state, timeout) do
    case Frame.evaluate(state.frame_id,
           expression: "() => performance.timeOrigin",
           is_function: true,
           timeout: timeout
         ) do
      {:ok, identity} -> identity
      {:error, error} -> raise "Could not identify the navigated document: #{inspect(error)}"
    end
  end

  defp navigation_target(state, destination) do
    "destination #{inspect(destination)} (page #{inspect(state.page_id)}, frame #{inspect(state.frame_id)})"
  end

  defp timeout do
    :fluffy
    |> Application.fetch_env!(:playwright)
    |> Keyword.fetch!(:timeout)
  end

  defp subscribe_to_console!(page_id, connection, subscription_timeout \\ timeout()) do
    config = Application.fetch_env!(:fluffy, :playwright)

    if Keyword.get(config, :js_logger, Fluffy.Playwright.ConsoleLogger) != false do
      case BrowserPage.update_subscription(page_id,
             event: :console,
             enabled: true,
             connection: connection,
             timeout: subscription_timeout
           ) do
        {:ok, _result} -> :ok
        {:error, error} -> raise "Could not enable Playwright console logging: #{inspect(error)}"
      end
    end
  end

  defp normalize_browser_context_options(options) do
    Enum.map(options, fn
      {:bypass_csp, value} ->
        {:bypassCSP, value}

      {key, :no_preference} when key in [:color_scheme, :contrast, :reduced_motion] ->
        {protocol_option_key(key), "no-preference"}

      option ->
        option
    end)
  end

  defp protocol_option_key(:color_scheme), do: :colorScheme
  defp protocol_option_key(:reduced_motion), do: :reducedMotion
  defp protocol_option_key(key), do: key

  defp deduplicate_headers(headers) do
    Enum.reduce(headers, [], fn {name, value}, result ->
      put_header(result, {String.downcase(to_string(name)), value})
    end)
  end

  defp put_header(headers, nil), do: headers

  defp put_header(headers, {name, value}) do
    headers
    |> Enum.reject(fn {header_name, _value} ->
      String.downcase(to_string(header_name)) == name
    end)
    |> Kernel.++([{name, value}])
  end
end
