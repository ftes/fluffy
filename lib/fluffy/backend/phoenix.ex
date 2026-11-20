defmodule Fluffy.Backend.Phoenix do
  @moduledoc false

  @behaviour Fluffy.Backend.Contract

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Fluffy.Backend.Phoenix.Context
  alias Fluffy.Backend.Phoenix.CookieJar
  alias Fluffy.Backend.Phoenix.HTTP
  alias Fluffy.Backend.Phoenix.HTTP.Client, as: HTTPClient
  alias Fluffy.Backend.Phoenix.HTTP.Response, as: HTTPResponse
  alias Fluffy.Download
  alias Fluffy.Driver.Live, as: LiveDriver
  alias Fluffy.Driver.NoDocument
  alias Fluffy.Driver.Phoenix.ClientDOM
  alias Fluffy.Driver.Phoenix.Form
  alias Fluffy.Driver.Static.State, as: StaticState
  alias Fluffy.Internal.Navigation
  alias Fluffy.Internal.Navigation.Link
  alias Fluffy.Internal.Navigation.Redirect
  alias Fluffy.Internal.Navigation.StaticConn
  alias Fluffy.Internal.Navigation.Submission
  alias Fluffy.Internal.NavigationFailure
  alias Fluffy.Page
  alias Fluffy.Session

  # Phoenix.LiveViewTest.live/1 expands a path-taking branch that reads the
  # caller's @endpoint. Fluffy calls the conn-only branch after dispatching
  # through the endpoint stored in the session, so this value is never used.
  @endpoint nil
  @live_flash_cookie "__phoenix_flash__"
  # A browser aborts a navigation answered with no content and keeps the
  # current document; 205 does not reset forms in any engine.
  @no_content_statuses [204, 205]

  @impl true
  def start_session(options) do
    # No sandbox header: requests and LiveViews run in the test process or with it in
    # `$callers`, so they use its sandbox connection, as with Phoenix.ConnTest.
    context = %Context{
      http: %HTTPClient{
        base_url: Keyword.fetch!(options, :base_url),
        endpoint: Keyword.fetch!(options, :endpoint),
        cookie_jar: CookieJar.new(),
        initial_conn: Keyword.get(options, :conn),
        request_headers: request_headers(options[:extra_http_headers], options[:conn])
      }
    }

    page = %Page.State{driver: :unvisited, state: %NoDocument.State{}}
    Session.new(__MODULE__, context, page)
  end

  # The headers a browser context of the test sends with every request: its `locale` as
  # Accept-Language and `user_agent` as User-Agent (a `conn:`'s own win), the `conn:`'s Accept
  # and Authorization (as `Phoenix.ConnTest.recycle/2` keeps them), then the session's
  # `extra_http_headers`, else the test's, as in Playwright. `HTTP` puts later ones over earlier.
  defp request_headers(session_headers, conn) do
    use = Fluffy.TestInfo.fetch!().use

    derived =
      for {name, key} <- [{"accept-language", :locale}, {"user-agent", :user_agent}],
          do: {name, conn_header(conn, name) || use[key]}

    recycled = for name <- ["accept", "authorization"], do: {name, conn_header(conn, name)}
    extra = session_headers || use[:extra_http_headers] || []
    for {name, value} <- derived ++ recycled ++ Enum.to_list(extra), value != nil, do: {name, value}
  end

  defp conn_header(nil, _name), do: nil
  defp conn_header(conn, name), do: conn |> Plug.Conn.get_req_header(name) |> List.first()

  @doc false
  def session_for_html(html) when is_binary(html) do
    page = %Page.State{
      driver: :static,
      state: %StaticState{client_dom: ClientDOM.from_fragment(html)}
    }

    Session.new(
      __MODULE__,
      %Context{http: nil},
      page
    )
  end

  @impl true
  def page_snapshot(_context, page), do: page

  @impl true
  def commit_page(page, driver, state, url, options) do
    options = Keyword.validate!(options, same_document: false)

    %{
      page
      | driver: driver,
        state: state,
        url: url,
        document_id: if(options[:same_document], do: page.document_id, else: make_ref())
    }
  end

  @impl true
  def prepare_page(_context, page), do: {:ok, {page, nil, nil}}

  @impl true
  def subscribe_page(_context, _page, _runtime), do: :ok

  @impl true
  def runtime_event(_context, _message), do: :ignore

  @impl true
  def absolute_url(%Session{} = session, path) do
    Session.context(session).http.base_url |> URI.merge(path) |> URI.to_string()
  end

  @impl true
  def base_url(%Session{} = session), do: http!(session).base_url

  # The session's cookie jar plays the browser context's cookie store: requests send what
  # it holds when they are made, as a browser does.
  @impl true
  def add_cookies(%Session{} = session, cookies) do
    http = http!(session)
    put_http(session, %{http | cookie_jar: CookieJar.add_cookies(http.cookie_jar, cookies)})
  end

  @impl true
  def cookies(%Session{} = session, urls), do: CookieJar.cookies(http!(session).cookie_jar, urls)

  @impl true
  def clear_cookies(%Session{} = session, options) when is_list(options) or is_map(options) do
    filters = Fluffy.Options.validate_clear_cookies!(options)
    http = http!(session)
    put_http(session, %{http | cookie_jar: CookieJar.clear_cookies(http.cookie_jar, filters)})
  end

  # A session_for_html/2 session makes no requests.
  defp http!(session) do
    case Session.context(session).http do
      %HTTPClient{} = http -> http
      nil -> raise ArgumentError, "a session of session_for_html/2 has no base URL or cookies"
    end
  end

  @impl true
  def visit(%Session{} = session, path) do
    http = Session.context(session).http
    # A test that visits another origin has nothing in the app to check.
    url = HTTP.validate_url!(http, URI.merge(http.base_url, path))
    {http, response} = HTTP.request(http, url)
    session = put_http(session, http)

    # Playwright's goto fails when the browser aborts the navigation; the
    # browser keeps the cookies the response set.
    if match?(%{conn: %{status: status}} when status in @no_content_statuses, response) do
      raise NavigationFailure,
            "Phoenix visit to #{URI.to_string(response.request.url)} was aborted by HTTP #{response.conn.status}"
    end

    finish_response(session, response, nil)
  end

  @impl true
  def reload(%Session{} = session, _options \\ []) do
    case Session.current_page(session) do
      %Page.State{driver: driver} when driver in [:unvisited, :external] ->
        NoDocument.unsupported!(session, :reload)

      %Page.State{url: url} ->
        visit(session, url)
    end
  end

  @impl true
  def navigate(%Session{} = session, %Link{} = navigation) do
    follow_link(session, navigation.destination, navigation.download)
  end

  def navigate(%Session{} = session, %Submission{triggered: false} = navigation) do
    submit(session, navigation.submission, navigation.redirects)
  end

  # LiveView's client unloads its socket before it submits a triggered form.
  def navigate(%Session{} = session, %Submission{triggered: true} = navigation) do
    inert_if_kept(session, &submit(&1, navigation.submission, navigation.redirects))
  end

  # The view that redirected is gone.
  def navigate(%Session{} = session, %Redirect{} = navigation) do
    inert_if_kept(session, &follow_redirect(&1, navigation.destination, navigation.flash, navigation.redirects))
  end

  def navigate(%Session{} = session, %StaticConn{conn: conn}) do
    destination = conn_request_target(conn, Session.current_page(session).url)
    commit_conn(session, conn, destination)
  end

  @impl true
  def event_source(session, :download, _scope), do: session.active_page

  def event_source(session, type, _scope) when type in [:page, :popup, :close, :load, :dom_content_loaded, :crash],
    do:
      Fluffy.CapabilityError.require_playwright!(
        session,
        :pages,
        type,
        "multiple pages, new tabs, and page lifecycle operations require Playwright"
      )

  def event_source(session, :file_chooser, _scope) do
    raise Fluffy.CapabilityError,
      capability: :file_chooser_events,
      operation: :file_chooser,
      driver: Session.current_driver(session),
      detail: "file_chooser events require a Playwright session"
  end

  # Dialogs, console, page errors, frames, workers, WebSockets and network events.
  def event_source(session, type, _scope) do
    raise Fluffy.CapabilityError,
      capability: :browser_events,
      operation: type,
      driver: Session.current_driver(session),
      detail: "#{type} events require a Playwright session"
  end

  @impl true
  def subscribe_event(_session, :download, _source, _pid), do: {fn _ -> :ignore end, fn -> :ok end}

  defp follow_link(%Session{} = session, href, download_name) do
    current_url = Session.current_page(session).url
    url = URI.merge(current_url || Session.context(session).http.base_url, href)

    if same_document_navigation?(current_url, url) do
      Session.commit_page(session, Session.current_driver(session), Session.page_state(session), URI.to_string(url),
        same_document: true
      )
    else
      request(session, url, :get, nil, download_name, 0)
    end
  end

  # Navigates away from a LiveView that is gone. A response that keeps the
  # document, such as a download, leaves it as inert markup.
  defp inert_if_kept(session, navigate) do
    document_id = Session.current_page(session).document_id
    session = navigate.(session)

    if Session.current_page(session).document_id == document_id, do: keep_document(session, nil), else: session
  end

  defp submit(%Session{} = session, submission, redirects) do
    current_url = Session.current_page(session).url
    url = URI.merge(current_url, submission.action)

    case submission.method do
      :get ->
        encoded_fields = Form.url_encode(submission.fields)
        request(session, %{url | query: encoded_fields}, :get, nil, nil, redirects)

      :post ->
        request(session, url, :post, encode_post_submission(submission), nil, redirects)
    end
  end

  defp encode_post_submission(%{enctype: "multipart/form-data", fields: fields}) do
    boundary = "----FluffyFormBoundary#{System.unique_integer([:positive, :monotonic])}"

    %{
      body: Form.multipart_encode(fields, boundary),
      content_type: "multipart/form-data; boundary=#{boundary}"
    }
  end

  defp encode_post_submission(%{fields: fields}), do: Form.url_encode(fields)

  defp commit_live(%Session{} = session, view, html, destination, redirects) do
    url =
      URI.merge(Session.current_page(session).url || Session.context(session).http.base_url, destination)

    # A redirect the view reported right after mounting is followed now; the
    # mounted document commits first, so the view is released like any other.
    {state, redirect} = LiveDriver.mount(session.runtime, view, html)
    session = replace_document(session, :live, state, URI.to_string(url))

    # The client patches the join render before anything the view sends later, so
    # a form that render triggers wins over a redirect reported after the join. It
    # counts toward the redirects that led here (see docs/capabilities.md).
    case {ClientDOM.triggered_submission(state.client_dom), redirect} do
      {nil, nil} ->
        session

      {nil, redirect} ->
        follow_mount_redirect(session, redirect, url, redirects)

      {submission, _later_redirect} ->
        navigate(
          session,
          Navigation.submission(submission, redirects: Navigation.count_redirect!(redirects, url), triggered: true)
        )
    end
  end

  # A browser follows a redirect from a view's mount like an HTTP redirect, so
  # it counts toward the same redirect limit.
  defp follow_mount_redirect(session, {_kind, %{to: destination} = options}, url, redirects) do
    follow_redirect(session, destination, options[:flash], Navigation.count_redirect!(redirects, url))
  end

  # Requests a view's redirect destination, after `redirects` redirects so far,
  # with the flash it carries.
  defp follow_redirect(session, destination, flash, redirects) do
    url = URI.merge(Session.context(session).http.base_url, destination)

    session
    |> put_live_redirect_flash(flash)
    |> request(url, :get, nil, nil, redirects)
  end

  @doc false
  def commit_conn(%Session{} = session, conn, destination) do
    url =
      URI.merge(Session.current_page(session).url || Session.context(session).http.base_url, destination)

    {http, response} = HTTP.follow(Session.context(session).http, conn, url)
    session |> put_http(http) |> finish_response(response, nil)
  end

  defp request(session, url, method, body, download_name, redirects) do
    {http, response} = HTTP.request(Session.context(session).http, url, method, body, redirects)
    session |> put_http(http) |> finish_response(response, download_name)
  end

  # Like the LiveView client's Browser.redirect, a redirect's flash travels to
  # the next page in a 60-second __phoenix_flash__ cookie, signed as
  # LiveViewTest's follow_redirect signs a flash that is still a map. The
  # client sets it on the app's own origin, even before leaving it.
  defp put_live_redirect_flash(session, nil), do: session

  defp put_live_redirect_flash(session, flash) do
    token =
      if is_map(flash),
        do: Phoenix.LiveView.Utils.sign_flash(Session.context(session).http.endpoint, flash),
        else: flash

    http =
      HTTP.store_cookie_header(
        Session.context(session).http,
        URI.parse(Session.context(session).http.base_url),
        "#{@live_flash_cookie}=#{token}; Path=/; Max-Age=60"
      )

    put_http(session, http)
  end

  defp finish_response(session, %HTTPResponse{conn: nil, request: %{url: url}}, _download_name),
    do: commit_external(session, url)

  defp finish_response(session, %HTTPResponse{conn: %{status: status} = conn}, _download_name)
       when status in @no_content_statuses, do: keep_document(session, conn)

  defp finish_response(session, %HTTPResponse{conn: conn, request: %{url: url}} = response, download_name) do
    case capture_download(conn, session, url, download_name) do
      {:ok, session} -> session
      :not_a_download -> commit_response(conn, session, url, response.redirects)
    end
  end

  # LiveView's client disconnects before every HTTP navigation it lets through,
  # so a kept LiveView document remains as inert markup. Its conn is the
  # no-content response's, the session's latest, or none after a download.
  defp keep_document(session, conn) do
    case Session.current_page(session) do
      %Page.State{driver: :live, state: state, url: url} ->
        state = %StaticState{client_dom: state.client_dom, conn: conn}
        replace_document(session, :static, state, url, same_document: true)

      %Page.State{} ->
        session
    end
  end

  defp commit_response(%{assigns: %{live_module: _module}} = conn, session, url, redirects) do
    mounted_url = Plug.Conn.request_url(conn)

    case live(conn) do
      {:ok, view, html} ->
        commit_live(session, view, html, URI.to_string(url), redirects)

      # LiveView rejected the connection as stale or unauthorized. LiveViewTest
      # reports that as a redirect to the URL being mounted, where the LiveView
      # client would reload the page, so following it would only loop.
      {:error, {:redirect, %{to: ^mounted_url} = options} = reason} when map_size(options) == 1 ->
        raise NavigationFailure,
              "LiveView navigation failed: LiveView rejected the connection to #{mounted_url} as stale or " <>
                "unauthorized, such as for a live_session or on_mount mismatch: #{inspect(reason)}"

      # The view redirected in its connected mount. A browser follows it.
      {:error, {kind, %{to: _destination}} = redirect} when kind in [:live_redirect, :redirect] ->
        follow_mount_redirect(session, redirect, url, redirects)

      {:error, reason} ->
        raise NavigationFailure, "LiveView navigation failed: #{inspect(reason)}"
    end
  end

  defp commit_response(%{status: status} = conn, session, url, _redirects) when status in 200..599 do
    commit_static(conn, session, url)
  end

  defp commit_response(conn, _session, url, _redirects) do
    raise NavigationFailure, "Phoenix navigation failed with HTTP #{conn.status} for #{URI.to_string(url)}"
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
        page: Session.handle(session),
        body: conn.resp_body
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

  defp commit_static(conn, session, url) do
    state = %StaticState{
      conn: conn,
      client_dom: ClientDOM.from_document(conn.resp_body)
    }

    replace_document(session, :static, state, URI.to_string(url))
  end

  # A browser leaves the app for an off-origin request. The test can still
  # check where it went, so commit a page with that URL and no document.
  # Its URL reads as a browser reports it, with a lowercase host and at least a `/` path.
  defp commit_external(session, url) do
    url = %{url | host: String.downcase(url.host), path: if(url.path in [nil, ""], do: "/", else: url.path)}
    replace_document(session, :external, %NoDocument.State{}, URI.to_string(url))
  end

  # The page's previous document stops its LiveView before the new one commits.
  defp replace_document(session, driver, state, url, options \\ []) do
    :ok = release_page(session, Session.current_page(session))
    Session.commit_page(session, driver, state, url, options)
  end

  defp release_page(session, %Page.State{driver: :live} = page), do: LiveDriver.release(session, page)
  defp release_page(_session, %Page.State{}), do: :ok
end
