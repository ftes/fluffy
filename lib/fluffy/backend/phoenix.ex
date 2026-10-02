defmodule Fluffy.Backend.Phoenix do
  @moduledoc false

  @behaviour Fluffy.Backend.Contract

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Fluffy.Backend.Phoenix.Context
  alias Fluffy.Backend.Phoenix.HTTP
  alias Fluffy.Backend.Phoenix.HTTP.Client, as: HTTPClient
  alias Fluffy.Backend.Phoenix.HTTP.Response, as: HTTPResponse
  alias Fluffy.ClientDOM
  alias Fluffy.Download
  alias Fluffy.Driver.Live, as: LiveDriver
  alias Fluffy.Driver.Live.State, as: LiveState
  alias Fluffy.Driver.Live.UploadState
  alias Fluffy.Driver.Static.State, as: StaticState
  alias Fluffy.Driver.Unvisited.State, as: UnvisitedState
  alias Fluffy.Internal.Navigation.Link
  alias Fluffy.Internal.Navigation.Patch
  alias Fluffy.Internal.Navigation.Redirect
  alias Fluffy.Internal.Navigation.StaticConn
  alias Fluffy.Internal.Navigation.Submission
  alias Fluffy.LiveViewWatcher
  alias Fluffy.Page
  alias Fluffy.PageLifecycle
  alias Fluffy.Session

  # Phoenix.LiveViewTest.live/1 expands a path-taking branch that reads the
  # caller's @endpoint. Fluffy calls the conn-only branch after dispatching
  # through the endpoint stored in the session, so this value is never used.
  @endpoint nil
  @live_flash_cookie "__phoenix_flash__"

  @impl true
  def start_session(options, attachment) do
    {resource_scope, runtime, sandbox_header} = attachment

    context = %Context{
      http: %HTTPClient{
        base_url: Keyword.fetch!(options, :base_url),
        endpoint: Keyword.fetch!(options, :endpoint),
        cookie_jar: Fluffy.CookieJar.new(),
        initial_conn: Keyword.get(options, :conn),
        request_headers: put_header(Keyword.get(options, :headers, []), sandbox_header)
      },
      resource_scope: resource_scope,
      timeout: Keyword.get(options, :timeout, Application.get_env(:fluffy, :timeout, 1_000))
    }

    page = %Page.State{driver: :unvisited, state: %UnvisitedState{}}
    Session.new(__MODULE__, context, page, runtime)
  end

  @doc false
  def session_for_html(html) when is_binary(html) do
    page = %Page.State{
      driver: :static,
      state: %StaticState{client_dom: ClientDOM.from_fragment(html)}
    }

    Session.new(
      __MODULE__,
      %Context{http: nil, resource_scope: nil, timeout: 1_000},
      page
    )
  end

  @impl true
  def page_snapshot(_context, page), do: page

  @impl true
  def page_status(_context, page), do: page.status

  @impl true
  def commit_page(page, driver, state, url, options) do
    options = Keyword.validate!(options, status: page.status, same_document: false)

    %{
      page
      | driver: driver,
        state: state,
        url: url,
        status: options[:status],
        document_id: if(options[:same_document], do: page.document_id, else: make_ref())
    }
  end

  @impl true
  def prepare_page(_context, page), do: {:ok, {page, nil, nil}}

  @impl true
  def subscribe_page(_context, _page, _runtime), do: :ok

  @impl true
  def runtime_event(_context, _message), do: :ignore

  @doc false
  def register_process(runtime, kind, pid, timeout) do
    Fluffy.SessionRuntime.register(runtime, {kind, pid}, fn -> stop_process(pid, timeout, :shutdown) end)
  end

  @impl true
  def run_step(%Session{} = _session, _name, _location, fun), do: fun.()

  @impl true
  def capture_failure(%Session{}, _operation, _error, _stacktrace), do: :ok

  @impl true
  def normalize_error(session, operation, arguments, error),
    do: Fluffy.Internal.OperationFailure.normalize(session, operation, arguments, error)

  @impl true
  def absolute_url(%Session{} = session, path) do
    Session.context(session).http.base_url |> URI.merge(path) |> URI.to_string()
  end

  @impl true
  def visit(%Session{} = session, path) do
    url = resolve_url(Session.context(session).http.base_url, path, session)

    request(session, url)
  end

  @impl true
  def reload(%Session{} = session, options \\ []) do
    _options = Keyword.validate!(options, [:timeout])

    case Session.current_page(session).url do
      nil ->
        raise ArgumentError, "cannot reload before the first visit"

      url ->
        visit(session, url)
    end
  end

  @impl true
  def navigate(%Session{} = session, %Link{} = navigation) do
    follow_link(session, navigation.destination, navigation.download)
  end

  def navigate(%Session{} = session, %Submission{} = navigation) do
    submit(session, navigation.submission)
  end

  def navigate(%Session{} = session, %Redirect{} = navigation) do
    session
    |> put_live_redirect_flash(navigation.destination, navigation.flash)
    |> visit(navigation.destination)
  end

  def navigate(%Session{} = session, %Patch{} = navigation) do
    previous_url = Session.current_page(session).url
    url = resolve_url(previous_url, navigation.destination, session)

    Session.commit_page(session, :live, navigation.state, URI.to_string(url), same_document: true)
  end

  def navigate(%Session{} = session, %StaticConn{conn: conn}) do
    destination = conn_request_target(conn, Session.current_page(session).url)
    commit_conn(session, conn, destination)
  end

  @impl true
  @spec new_page(Session.t()) :: no_return()
  def new_page(session), do: require_browser_pages!(session)

  @impl true
  @spec history(Session.t(), :go_back | :go_forward, keyword()) :: no_return()
  def history(session, _direction, _options), do: require_browser_pages!(session)

  @impl true
  @spec close_page(Session.t(), Page.t()) :: no_return()
  def close_page(%Session{} = session, _page_id) do
    require_browser_pages!(session)
  end

  @impl true
  def event_source(session, :download, _scope), do: session.active_page

  def event_source(session, type, _scope) when type in [:page, :popup], do: require_browser_pages!(session)

  def event_source(session, type, _scope) do
    capability =
      case type do
        :dialog -> :browser_dialogs
        :file_chooser -> :file_chooser_events
        :frame_navigated -> :browser_frame_events
        type when type in [:request, :response] -> :browser_network_events
      end

    raise Fluffy.CapabilityError,
      capability: capability,
      driver: Session.current_driver(session),
      detail: "#{type} events require a Playwright session"
  end

  @impl true
  def subscribe_event(_session, :download, _source, _pid), do: {fn _ -> :ignore end, fn -> :ok end}

  defp follow_link(%Session{} = session, href, download_name) do
    current_url = Session.current_page(session).url
    url = resolve_url(current_url || Session.context(session).http.base_url, href, session)

    if same_document_navigation?(current_url, url) do
      Session.commit_page(session, Session.current_driver(session), Session.page_state(session), URI.to_string(url),
        same_document: true
      )
    else
      request(session, url, :get, nil, download_name)
    end
  end

  defp require_browser_pages!(session) do
    raise Fluffy.CapabilityError,
      capability: :pages,
      driver: Session.current_driver(session),
      detail: "multiple pages, new tabs, and page lifecycle operations require Playwright"
  end

  defp submit(%Session{} = session, submission) do
    current_url = Session.current_page(session).url
    url = resolve_url(current_url, submission.action, session)

    case submission.method do
      :get ->
        encoded_fields = Fluffy.Form.url_encode(submission.fields)
        request(session, %{url | query: encoded_fields}, :get, nil)

      :post ->
        request(session, url, :post, encode_post_submission(submission))
    end
  end

  defp encode_post_submission(%{enctype: "multipart/form-data", fields: fields}) do
    boundary = "----FluffyFormBoundary#{System.unique_integer([:positive, :monotonic])}"

    %{
      body: Fluffy.Form.multipart_encode(fields, boundary),
      content_type: "multipart/form-data; boundary=#{boundary}"
    }
  end

  defp encode_post_submission(%{fields: fields}), do: Fluffy.Form.url_encode(fields)

  @doc false
  def commit_live(%Session{} = session, conn, view, destination) do
    proxy_pid = live_view_proxy_pid(view)
    Process.unlink(proxy_pid)

    url =
      resolve_url(
        Session.current_page(session).url || Session.context(session).http.base_url,
        destination,
        session
      )

    {:ok, watcher} =
      DynamicSupervisor.start_child(
        Fluffy.SessionRuntime.Supervisor,
        {LiveViewWatcher, caller: self(), view: view}
      )

    :ok = register_process(session.runtime, :watcher, watcher, Session.context(session).timeout)

    :ok =
      register_process(session.runtime, :live_view, view.pid, Session.context(session).timeout)

    :ok =
      register_process(session.runtime, :live_view, proxy_pid, Session.context(session).timeout)

    state = %LiveState{
      client_dom: ClientDOM.from_fragment(render(view)),
      live_uploads: UploadState.new(),
      view: view,
      watcher: watcher
    }

    PageLifecycle.replace_document(session, :live, state, URI.to_string(url), [status: conn.status], &release_page/3)
  end

  @doc false
  def commit_conn(%Session{} = session, conn, destination) do
    url =
      resolve_url(
        Session.current_page(session).url || Session.context(session).http.base_url,
        destination,
        session
      )

    {http, response} = HTTP.follow(Session.context(session).http, conn, url)
    session |> put_http(http) |> finish_response(response, nil)
  end

  defp request(session, url, method \\ :get, body \\ nil, download_name \\ nil) do
    {http, response} = HTTP.request(Session.context(session).http, url, method, body)
    session |> put_http(http) |> finish_response(response, download_name)
  end

  defp put_live_redirect_flash(session, _destination, nil), do: session

  defp put_live_redirect_flash(session, destination, flash) do
    token =
      if is_map(flash),
        do: Phoenix.LiveView.Utils.sign_flash(Session.context(session).http.endpoint, flash),
        else: flash

    url = resolve_url(Session.context(session).http.base_url, destination, session)

    http =
      HTTP.store_cookie_header(
        Session.context(session).http,
        url,
        "#{@live_flash_cookie}=#{token}; Path=/; Max-Age=60"
      )

    put_http(session, http)
  end

  defp finish_response(session, %HTTPResponse{conn: conn, request: %{url: url}}, download_name) do
    case capture_download(conn, session, url, download_name) do
      {:ok, session} -> session
      :not_a_download -> commit_response(conn, session, url)
    end
  end

  defp commit_response(%{assigns: %{live_module: _module}} = conn, session, url) do
    case live(conn) do
      {:ok, view, _html} ->
        commit_live(session, conn, view, URI.to_string(url))

      {:error, reason} ->
        raise "LiveView navigation failed: #{inspect(reason)}"
    end
  end

  defp commit_response(%{status: status} = conn, session, url) when status in 200..599 do
    commit_static(conn, session, url)
  end

  defp commit_response(conn, _session, url) do
    raise "Phoenix navigation failed with HTTP #{conn.status} for #{URI.to_string(url)}"
  end

  defp resolve_url(base_url, path, session) do
    HTTP.resolve(Session.context(session).http, base_url, path)
  end

  defp put_http(%Session{} = session, %HTTPClient{} = http) do
    Session.put_context(session, %{Session.context(session) | http: http})
  end

  defp same_document_navigation?(nil, _url), do: false

  defp same_document_navigation?(current_url, url) do
    current = URI.parse(current_url)

    %{current | fragment: nil} == %{url | fragment: nil} and
      (current.fragment != url.fragment or not is_nil(url.fragment))
  end

  defp conn_request_target(%Plug.Conn{} = conn, current_url) do
    path =
      if conn.request_path in [nil, ""],
        do: URI.parse(current_url).path || "/",
        else: conn.request_path

    if conn.query_string in [nil, ""] do
      path
    else
      path <> "?" <> conn.query_string
    end
  end

  defp capture_download(conn, session, url, download_name) do
    disposition = response_header(conn, "content-disposition")

    if not is_nil(download_name) or attachment?(disposition) do
      download = %Download{
        suggested_filename: suggested_filename(disposition, download_name, url),
        url: URI.to_string(url),
        runtime: session.runtime,
        source: conn.resp_body
      }

      :ok = Fluffy.SessionRuntime.emit_event(session.runtime, session.active_page, :download, download)
      # Downloads keep the source document, whether or not anyone observes them.
      {:ok, session}
    else
      :not_a_download
    end
  end

  defp attachment?(nil), do: false

  defp attachment?(disposition) do
    disposition
    |> String.split(";", parts: 2)
    |> hd()
    |> String.trim()
    |> String.downcase()
    |> Kernel.==("attachment")
  end

  defp suggested_filename(disposition, download_name, url) do
    disposition_filename(disposition) ||
      non_empty_filename(download_name) ||
      url_filename(url) ||
      "download"
  end

  defp disposition_filename(nil), do: nil

  defp disposition_filename(disposition) do
    params = Plug.Conn.Utils.params(disposition)

    case params["filename*"] do
      nil -> non_empty_filename(params["filename"])
      encoded -> decode_extended_filename(encoded) || non_empty_filename(params["filename"])
    end
  end

  defp decode_extended_filename(encoded) do
    case String.split(encoded, "'", parts: 3) do
      [charset, _language, value] when charset in ["UTF-8", "utf-8"] -> URI.decode(value)
      _other -> nil
    end
  end

  defp non_empty_filename(value) when value in [nil, ""], do: nil
  defp non_empty_filename(value), do: value |> Path.basename() |> String.replace("\\", "_")

  defp url_filename(url) do
    case url.path |> Kernel.||("") |> Path.basename() |> URI.decode() do
      value when value in ["", "/", "."] -> nil
      value -> value
    end
  end

  defp response_header(conn, name) do
    conn
    |> Plug.Conn.get_resp_header(name)
    |> List.first()
  end

  defp put_header(headers, nil), do: headers

  defp put_header(headers, {name, value}) do
    headers
    |> Enum.reject(fn {header_name, _value} ->
      String.downcase(to_string(header_name)) == name
    end)
    |> Kernel.++([{name, value}])
  end

  defp commit_static(conn, session, url) do
    state = %StaticState{
      conn: conn,
      client_dom: ClientDOM.from_document(conn.resp_body)
    }

    PageLifecycle.replace_document(session, :static, state, URI.to_string(url), [status: conn.status], &release_page/3)
  end

  defp release_page(session, %Page.State{driver: :live} = page, _reason) do
    proxy_pid = live_view_proxy_pid(page.state.view)
    :ok = LiveDriver.release_page_uploads(session, page)
    stop_process(page.state.watcher, Session.context(session).timeout, :normal)
    Fluffy.SessionRuntime.release(session.runtime, {:watcher, page.state.watcher})
    stop_process(page.state.view.pid, Session.context(session).timeout, :normal)
    stop_process(proxy_pid, Session.context(session).timeout, :normal)

    Fluffy.SessionRuntime.release(session.runtime, {:live_view, page.state.view.pid})

    Fluffy.SessionRuntime.release(session.runtime, {:live_view, proxy_pid})

    flush_watcher_event(page.state.watcher)
    :ok
  end

  defp release_page(_session, %Page.State{}, _reason), do: :ok

  defp flush_watcher_event(watcher) do
    receive do
      {:fluffy_live_view, ^watcher, _event} -> :ok
    after
      0 -> :ok
    end
  end

  defp live_view_proxy_pid(%{proxy: {_reference, _topic, proxy_pid}}) when is_pid(proxy_pid), do: proxy_pid

  defp stop_process(pid, timeout, reason) do
    if Process.alive?(pid) do
      reference = Process.monitor(pid)

      try do
        request_stop(pid, timeout, reason)
      catch
        :exit, _reason -> Process.exit(pid, :kill)
      end

      receive do
        {:DOWN, ^reference, :process, ^pid, _reason} -> :ok
      after
        timeout ->
          Process.exit(pid, :kill)

          receive do
            {:DOWN, ^reference, :process, ^pid, _reason} -> :ok
          end
      end
    end

    :ok
  end

  # Replacing a document stops its linked processes normally in the caller;
  # runtime teardown sends shutdown from the resource owner.
  defp request_stop(pid, timeout, :normal) do
    Process.unlink(pid)
    GenServer.stop(pid, :normal, timeout)
  end

  defp request_stop(pid, _timeout, :shutdown), do: Process.exit(pid, :shutdown)
end
