defmodule Fluffy.Internal.SessionCookie do
  @moduledoc false

  # The session cookie `Fluffy.add_session_cookie/3` adds: the endpoint's own `Plug.Session` runs on a
  # bare conn with the endpoint's `secret_key_base`, so the cookie is signed or encrypted as the
  # app's requests would write it. A renewed session, as a fresh login writes, holding only
  # `values`.

  @doc "The cookie map for `Fluffy.add_cookies/2` holding `values` as the endpoint's session, for `url`'s host."
  @spec new!(module() | nil, map() | keyword(), keyword() | nil, String.t()) :: map()
  def new!(endpoint, values, session_options, url) do
    endpoint = endpoint!(endpoint)
    options = session_options || session_options!(endpoint)

    conn =
      :get
      |> Plug.Test.conn("/")
      |> Map.put(:secret_key_base, endpoint.config(:secret_key_base))
      |> Plug.Session.call(Plug.Session.init(options))
      |> Plug.Conn.fetch_session()
      |> Plug.Conn.configure_session(renew: true)

    conn =
      values
      |> Enum.reduce(conn, fn {key, value}, conn -> Plug.Conn.put_session(conn, key, value) end)
      |> Plug.Conn.send_resp(200, "")

    key = Keyword.fetch!(options, :key)
    cookie = Map.fetch!(conn.resp_cookies, key)

    # Every attribute of the cookie Plug writes, so it replaces the app's own. `domain:` and
    # `path:` rather than `url:`, which would set `secure` from the URL's scheme alone: Plug's
    # path defaults to "/", and its `domain` matches subdomains too, as a leading dot says in
    # Playwright.
    uri = URI.parse(url)

    %{
      name: key,
      value: cookie.value,
      domain: domain(cookie[:domain], uri.host),
      path: Map.get(cookie, :path, "/"),
      httpOnly: Map.get(cookie, :http_only, true),
      secure: Map.get(cookie, :secure, uri.scheme == "https")
    }
    |> put_same_site(cookie[:same_site])
    |> put_expires(cookie[:max_age])
  end

  defp domain(nil, host), do: host
  defp domain("." <> _rest = domain, _host), do: domain
  defp domain(domain, _host), do: "." <> domain

  defp endpoint!(nil) do
    raise ArgumentError, """
    Fluffy.add_session_cookie/3: the session has no Phoenix endpoint to sign its cookie with; configure:

        config :fluffy, endpoint: MyAppWeb.Endpoint

    or pass `endpoint:` to `start_session/2`
    """
  end

  defp endpoint!(endpoint), do: endpoint

  defp session_options!(endpoint) do
    if Code.ensure_loaded?(endpoint) and function_exported?(endpoint, :session_options, 0) do
      endpoint.session_options()
    else
      raise ArgumentError, """
      Fluffy.add_session_cookie/3: #{inspect(endpoint)} does not expose its Plug.Session options; add to it:

          def session_options, do: @session_options

      or pass `session_options:` to `Fluffy.add_session_cookie/3`
      """
    end
  end

  defp put_same_site(cookie, nil), do: cookie
  defp put_same_site(cookie, same_site), do: Map.put(cookie, :sameSite, String.capitalize(same_site))

  defp put_expires(cookie, nil), do: cookie
  defp put_expires(cookie, max_age), do: Map.put(cookie, :expires, System.system_time(:second) + max_age)
end
