defmodule Fluffy.Backend.Phoenix.HTTP.Client do
  @moduledoc false

  @enforce_keys [:base_url, :cookie_jar, :endpoint, :request_headers]
  defstruct [:base_url, :cookie_jar, :endpoint, :initial_conn, :request_headers]

  @type t :: %__MODULE__{
          base_url: String.t(),
          cookie_jar: Fluffy.CookieJar.t(),
          endpoint: module(),
          initial_conn: Plug.Conn.t() | nil,
          request_headers: [{String.t(), String.t()}]
        }
end

defmodule Fluffy.Backend.Phoenix.HTTP.Request do
  @moduledoc false

  @enforce_keys [:body, :method, :url]
  defstruct [:body, :method, :url]

  @type t :: %__MODULE__{body: term(), method: :get | :post, url: URI.t()}
end

defmodule Fluffy.Backend.Phoenix.HTTP.Response do
  @moduledoc false

  @enforce_keys [:conn, :redirects, :request]
  defstruct [:conn, :redirects, :request, :external_url]

  # An off-origin request is not sent: `external_url` is its URL, and `conn` is nil.
  @type t :: %__MODULE__{
          conn: Plug.Conn.t() | nil,
          redirects: non_neg_integer(),
          request: Fluffy.Backend.Phoenix.HTTP.Request.t(),
          external_url: URI.t() | nil
        }
end

defmodule Fluffy.Backend.Phoenix.HTTP do
  @moduledoc false

  # Requests dispatch through Phoenix.ConnTest, but navigate like a browser:
  # ConnTest follows no redirects, and its recycling carries every response
  # cookie to the next request whatever its path, domain or expiry, so
  # redirects are followed here and cookies kept in a CookieJar.

  import Phoenix.ConnTest

  alias Fluffy.Backend.Phoenix.HTTP.Client
  alias Fluffy.Backend.Phoenix.HTTP.Request
  alias Fluffy.Backend.Phoenix.HTTP.Response
  alias Fluffy.CookieJar

  @redirect_statuses [301, 302, 303, 307, 308]
  @max_redirects 20

  # `redirects` counts the hops that led here, including LiveView mount
  # redirects, so a redirect loop through either fails at the same limit.
  # A browser leaves the app for an off-origin request, whether a link, a form
  # or a redirect hop, so it isn't sent: the response reports where it went.
  def request(%Client{} = client, %URI{} = url, method \\ :get, body \\ nil, redirects \\ 0) do
    request = %Request{body: body, method: method, url: url}

    if external?(client, url) do
      {client, %Response{conn: nil, redirects: redirects, request: request, external_url: url}}
    else
      client
      |> dispatch_request(%{request | url: validate_url!(client, url)})
      |> follow_redirects(redirects)
    end
  end

  def count_redirect!(redirects, %URI{} = url) when redirects >= @max_redirects do
    raise "Phoenix request exceeded #{@max_redirects} redirects at #{URI.to_string(url)}"
  end

  def count_redirect!(redirects, %URI{}), do: redirects + 1

  def follow(%Client{} = client, %Plug.Conn{} = conn, %URI{} = url, method \\ :get, body \\ nil) do
    request = %Request{body: body, method: method, url: validate_url!(client, url)}
    client = store_response_cookies(client, request.url, conn)
    follow_redirects({client, %Response{conn: conn, redirects: 0, request: request}}, 0)
  end

  def validate_url!(%Client{} = client, %URI{} = url) do
    cond do
      url.scheme not in ["http", "https"] ->
        raise Fluffy.CapabilityError,
          capability: :navigation_scheme,
          driver: :static,
          detail: "in-process navigation cannot dispatch the #{inspect(url.scheme)} scheme"

      external?(client, url) ->
        raise Fluffy.CapabilityError,
          capability: :external_navigation,
          driver: :static,
          detail: "cannot request #{URI.to_string(url)}; in-process navigation is limited to #{client.base_url}"

      true ->
        url
    end
  end

  def store_cookie_header(%Client{} = client, %URI{} = url, header) do
    %{client | cookie_jar: CookieJar.store_response(client.cookie_jar, url, [header])}
  end

  defp follow_redirects({client, %Response{} = response}, redirects) do
    conn = response.conn

    if conn.status in @redirect_statuses do
      case Plug.Conn.get_resp_header(conn, "location") do
        [] ->
          {client, response}

        [location | _rest] ->
          redirects = count_redirect!(redirects, response.request.url)

          {method, body} =
            redirected_request(conn.status, response.request.method, response.request.body)

          request(client, redirect_url(response.request.url, location), method, body, redirects)
      end
    else
      {client, %{response | redirects: redirects}}
    end
  end

  defp dispatch_request(%Client{} = client, %Request{} = request) do
    {client, conn} =
      request_conn(client, request.url, request_headers(request.method, request.body))

    conn =
      dispatch(
        conn,
        client.endpoint,
        request.method,
        request_target(request.url),
        request_body(request.body)
      )

    client = store_response_cookies(client, request.url, conn)
    {client, %Response{conn: conn, redirects: 0, request: request}}
  end

  defp request_conn(%Client{initial_conn: nil} = client, url, operation_headers) do
    {client, build_request_conn(build_conn(), client, url, operation_headers)}
  end

  defp request_conn(%Client{initial_conn: %Plug.Conn{} = initial_conn} = client, url, operation_headers) do
    cookie_jar = CookieJar.seed_request(client.cookie_jar, url, initial_conn)
    client = %{client | cookie_jar: cookie_jar, initial_conn: nil}
    conn = Plug.Conn.put_private(initial_conn, :phoenix_recycled, true)
    {client, build_request_conn(conn, client, url, operation_headers)}
  end

  defp build_request_conn(conn, client, url, operation_headers) do
    conn =
      Enum.reduce(client.request_headers ++ operation_headers, conn, fn {name, value}, conn ->
        Plug.Conn.put_req_header(conn, String.downcase(to_string(name)), to_string(value))
      end)

    conn = %{
      conn
      | host: url.host,
        port: effective_port(url),
        scheme: String.to_existing_atom(url.scheme)
    }

    case CookieJar.request_header(client.cookie_jar, url) do
      "" -> conn
      header -> Plug.Conn.put_req_header(conn, "cookie", header)
    end
  end

  defp store_response_cookies(client, url, conn) do
    cookie_jar =
      CookieJar.store_response(
        client.cookie_jar,
        url,
        Plug.Conn.get_resp_header(conn, "set-cookie")
      )

    %{client | cookie_jar: cookie_jar}
  end

  defp external?(%Client{} = client, %URI{scheme: scheme} = url) when scheme in ["http", "https"],
    do: origin(url) != origin(URI.parse(client.base_url))

  defp external?(%Client{}, %URI{}), do: false

  defp origin(%URI{} = url), do: {url.scheme, url.host, effective_port(url)}

  defp redirect_url(url, location) do
    redirect_url = URI.merge(url, location)

    if is_nil(URI.parse(location).fragment) and not is_nil(url.fragment),
      do: %{redirect_url | fragment: url.fragment},
      else: redirect_url
  end

  defp redirected_request(status, method, body) when status in [307, 308], do: {method, body}
  defp redirected_request(_status, _method, _body), do: {:get, nil}

  defp request_target(%URI{} = url) do
    path = if url.path in [nil, ""], do: "/", else: url.path
    if url.query, do: path <> "?" <> url.query, else: path
  end

  defp request_headers(:post, %{content_type: content_type}), do: [{"content-type", content_type}]
  defp request_headers(:post, _body), do: [{"content-type", "application/x-www-form-urlencoded"}]
  defp request_headers(_method, _body), do: []

  defp request_body(%{body: body}), do: body
  defp request_body(body), do: body

  defp effective_port(%URI{port: port}) when is_integer(port), do: port
  defp effective_port(%URI{scheme: "https"}), do: 443
  defp effective_port(%URI{}), do: 80
end
