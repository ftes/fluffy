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
  alias Fluffy.LiveViewWatcher
  alias Fluffy.Navigation.Link
  alias Fluffy.Navigation.Patch
  alias Fluffy.Navigation.Redirect
  alias Fluffy.Navigation.StaticConn
  alias Fluffy.Navigation.Submission
  alias Fluffy.NavigationEvent
  alias Fluffy.Page
  alias Fluffy.PageLifecycle
  alias Fluffy.Session
  alias Fluffy.TestScope

  # Phoenix.LiveViewTest.live/1 expands a path-taking branch that reads the
  # caller's @endpoint. Fluffy calls the conn-only branch after dispatching
  # through the endpoint stored in the session, so this value is never used.
  @endpoint nil
  @live_flash_cookie "__phoenix_flash__"

  @impl true
  def start_session(options, attachment) do
    {resource_scope, resource_id, sandbox_header} = TestScope.attachment_values(attachment)

    context = %Context{
      http: %HTTPClient{
        base_url: Keyword.fetch!(options, :base_url),
        endpoint: Keyword.fetch!(options, :endpoint),
        cookie_jar: Fluffy.CookieJar.new(),
        initial_conn: Keyword.get(options, :conn),
        request_headers: put_header(Keyword.get(options, :headers, []), sandbox_header)
      },
      resource_id: resource_id,
      resource_scope: resource_scope,
      timeout: Keyword.get(options, :timeout, Application.get_env(:fluffy, :timeout, 1_000))
    }

    page = %Page{id: :main, driver: :unvisited, state: %UnvisitedState{}}
    Session.new(__MODULE__, context, page)
  end

  @doc false
  def session_for_html(html) when is_binary(html) do
    page = %Page{
      id: :main,
      driver: :static,
      state: %StaticState{client_dom: ClientDOM.from_fragment(html)}
    }

    Session.new(
      __MODULE__,
      %Context{http: nil, resource_id: nil, resource_scope: nil, timeout: 1_000},
      page
    )
  end

  @impl true
  def close_session(%Session{} = session) do
    :ok = PageLifecycle.release_all(session, &release_page/3)

    case TestScope.close_session(
           Map.get(session.context, :resource_scope),
           Map.get(session.context, :resource_id)
         ) do
      :not_managed -> :ok
      :ok -> :ok
    end
  end

  @impl true
  def run_step(%Session{} = _session, _name, _location, fun), do: fun.()

  @impl true
  def capture_failure(%Session{}, _operation, _error, _stacktrace), do: :ok

  @impl true
  def absolute_url(%Session{} = session, path) do
    session.context.http.base_url |> URI.merge(path) |> URI.to_string()
  end

  @impl true
  def visit(%Session{backend: __MODULE__} = session, path) do
    url = resolve_url(session.context.http.base_url, path, session)

    request(session, url)
  end

  @impl true
  def reload(%Session{backend: __MODULE__} = session, options \\ []) do
    _options = Keyword.validate!(options, [:timeout])

    case Session.current_page(session).url do
      nil ->
        raise ArgumentError, "cannot reload before the first visit"

      url ->
        visit(session, url)
    end
  end

  @impl true
  def navigate(%Session{backend: __MODULE__} = session, %Link{} = navigation) do
    follow_link(session, navigation.destination, navigation.download)
  end

  def navigate(%Session{backend: __MODULE__} = session, %Submission{} = navigation) do
    submit(session, navigation.submission)
  end

  def navigate(%Session{backend: __MODULE__} = session, %Redirect{} = navigation) do
    session
    |> put_live_redirect_flash(navigation.destination, navigation.flash)
    |> visit(navigation.destination)
  end

  def navigate(%Session{backend: __MODULE__} = session, %Patch{} = navigation) do
    url = resolve_url(Session.current_page(session).url, navigation.destination, session)
    Session.commit_page(session, :live, navigation.state, URI.to_string(url))
  end

  def navigate(%Session{backend: __MODULE__} = session, %StaticConn{conn: conn}) do
    destination = conn_request_target(conn, Session.current_page(session).url)
    commit_conn(session, conn, destination)
  end

  @impl true
  @spec activate_page(Session.t(), term()) :: no_return()
  def activate_page(%Session{} = session, _page_id) do
    require_browser_pages!(session)
  end

  @impl true
  @spec close_page(Session.t(), term()) :: no_return()
  def close_page(%Session{} = session, _page_id) do
    require_browser_pages!(session)
  end

  @impl true
  def arm_event(%Session{} = session, :download, options) do
    %{token: token} = Session.pending_event(session)
    {:ok, session, %{type: :download, token: token, options: options}}
  end

  def arm_event(%Session{} = session, :navigation, options) do
    page = Session.current_page(session)

    {:ok, session,
     %{
       type: :navigation,
       page_id: page.id,
       revision: page.revision,
       from_url: page.url,
       options: options
     }}
  end

  def arm_event(%Session{} = session, :page, _options) do
    require_browser_pages!(session)
  end

  def arm_event(%Session{} = session, :dialog, _options) do
    raise Fluffy.CapabilityError,
      capability: :browser_dialogs,
      driver: Session.current_driver(session),
      detail: "the in-process drivers do not execute alert, confirm, prompt, or beforeunload"
  end

  def arm_event(%Session{} = session, :file_chooser, _options) do
    raise Fluffy.CapabilityError,
      capability: :file_chooser_events,
      driver: Session.current_driver(session),
      detail: "script-opened file chooser events are browser-owned and require a Playwright session"
  end

  def arm_event(%Session{} = session, type, _options) when type in [:request, :response] do
    raise Fluffy.CapabilityError,
      capability: :browser_network_events,
      driver: Session.current_driver(session),
      detail: "request and response event streams include browser subresources and currently require Playwright"
  end

  def arm_event(%Session{} = session, type, options) do
    {:ok, session, %{type: type, options: options}}
  end

  @impl true
  def await_event(
        %Session{pending_event: %{token: token, captured: value}} = session,
        %{type: :download, token: token},
        _timeout
      ) do
    {:ok, session, value}
  end

  def await_event(%Session{} = session, %{type: :navigation} = resource, _timeout) do
    page = Map.fetch!(session.pages, resource.page_id)

    if page.revision > resource.revision do
      {:ok, session,
       %NavigationEvent{
         from_url: resource.from_url,
         url: page.url,
         status: page.status
       }}
    else
      {:error, :timeout}
    end
  end

  def await_event(%Session{} = _session, _resource, _timeout), do: {:error, :timeout}

  @impl true
  def disarm_event(_resource), do: :ok

  defp follow_link(%Session{} = session, href, download_name) do
    current_url = Session.current_page(session).url
    url = resolve_url(current_url || session.context.http.base_url, href, session)

    if same_document_navigation?(current_url, url) do
      Session.commit_page(
        session,
        Session.current_driver(session),
        Session.page_state(session),
        URI.to_string(url)
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
        Session.current_page(session).url || session.context.http.base_url,
        destination,
        session
      )

    {:ok, watcher} =
      ExUnit.Callbacks.start_supervised(
        {LiveViewWatcher, caller: self(), view: view},
        id: make_ref()
      )

    :ok =
      TestScope.register_live_view(
        session.context.resource_scope,
        session.context.resource_id,
        view.pid
      )

    :ok =
      TestScope.register_live_view(
        session.context.resource_scope,
        session.context.resource_id,
        proxy_pid
      )

    state = %LiveState{
      client_dom: ClientDOM.from_fragment(render(view)),
      live_uploads: UploadState.new(),
      view: view,
      watcher: watcher
    }

    PageLifecycle.replace_document(
      session,
      :live,
      state,
      URI.to_string(url),
      [status: conn.status],
      &release_page/3
    )
  end

  @doc false
  def commit_conn(%Session{} = session, conn, destination) do
    url =
      resolve_url(
        Session.current_page(session).url || session.context.http.base_url,
        destination,
        session
      )

    {http, response} = HTTP.follow(session.context.http, conn, url)
    session |> put_http(http) |> finish_response(response, nil)
  end

  defp request(session, url, method \\ :get, body \\ nil, download_name \\ nil) do
    {http, response} = HTTP.request(session.context.http, url, method, body)
    session |> put_http(http) |> finish_response(response, download_name)
  end

  defp put_live_redirect_flash(session, _destination, nil), do: session

  defp put_live_redirect_flash(session, destination, flash) do
    token =
      if is_map(flash),
        do: Phoenix.LiveView.Utils.sign_flash(session.context.http.endpoint, flash),
        else: flash

    url = resolve_url(session.context.http.base_url, destination, session)

    http =
      HTTP.store_cookie_header(
        session.context.http,
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
    HTTP.resolve(session.context.http, base_url, path)
  end

  defp put_http(%Session{} = session, %HTTPClient{} = http) do
    %{session | context: %{session.context | http: http}}
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
      case Session.pending_event(session) do
        %{type: :download, token: token, options: options} ->
          bytes = conn.resp_body
          max_bytes = Keyword.fetch!(options, :max_bytes)

          if byte_size(bytes) > max_bytes do
            raise ExUnit.AssertionError,
              message: "Downloaded #{byte_size(bytes)} bytes, exceeding the configured :max_bytes limit of #{max_bytes}"
          end

          filename = suggested_filename(disposition, download_name, url)

          download = %Download{
            filename: filename,
            content_type: content_type(conn, filename),
            bytes: bytes,
            url: URI.to_string(url)
          }

          {:ok, Session.capture_pending_event(session, token, download)}

        _no_download_expectation ->
          # A browser keeps the source document when a response is downloaded.
          # Without an expectation there is no result to retain.
          {:ok, session}
      end
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

  defp content_type(conn, filename) do
    case response_header(conn, "content-type") do
      nil -> MIME.from_path(filename)
      value -> value |> String.split(";", parts: 2) |> hd() |> String.trim()
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

    PageLifecycle.replace_document(
      session,
      :static,
      state,
      URI.to_string(url),
      [status: conn.status],
      &release_page/3
    )
  end

  defp release_page(session, %Page{driver: :live} = page, _reason) do
    proxy_pid = live_view_proxy_pid(page.state.view)
    :ok = LiveDriver.release_page_uploads(session, page)
    stop_page_process(page.state.watcher, session.context.timeout)
    stop_page_process(page.state.view.pid, session.context.timeout)
    stop_page_process(proxy_pid, session.context.timeout)

    TestScope.release_live_view(
      session.context.resource_scope,
      session.context.resource_id,
      page.state.view.pid
    )

    TestScope.release_live_view(
      session.context.resource_scope,
      session.context.resource_id,
      proxy_pid
    )

    flush_watcher_event(page.state.watcher)
    :ok
  end

  defp release_page(_session, %Page{}, _reason), do: :ok

  defp stop_page_process(pid, timeout) do
    if Process.alive?(pid) do
      Process.unlink(pid)
      reference = Process.monitor(pid)

      try do
        GenServer.stop(pid, :normal, timeout)
      catch
        :exit, _reason -> if Process.alive?(pid), do: Process.exit(pid, :kill)
      end

      receive do
        {:DOWN, ^reference, :process, ^pid, _reason} -> :ok
      after
        timeout ->
          if Process.alive?(pid), do: Process.exit(pid, :kill)

          receive do
            {:DOWN, ^reference, :process, ^pid, _reason} -> :ok
          after
            timeout -> :ok
          end
      end
    end

    :ok
  end

  defp flush_watcher_event(watcher) do
    receive do
      {:fluffy_live_view, ^watcher, _event} -> :ok
    after
      0 -> :ok
    end
  end

  defp live_view_proxy_pid(%{proxy: {_reference, _topic, proxy_pid}}) when is_pid(proxy_pid), do: proxy_pid
end
