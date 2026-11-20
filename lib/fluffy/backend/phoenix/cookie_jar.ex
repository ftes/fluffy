defmodule Fluffy.Backend.Phoenix.CookieJar do
  @moduledoc false

  # A browser's cookie store for the Phoenix drivers. Cookies are kept as Playwright's
  # `browserContext.cookies()` reports them: a domain with a leading dot is a domain cookie,
  # one without is host-only (RFC 6265's host-only-flag), `expires` is unix seconds or `nil`
  # for a session cookie, and a cookie without SameSite reports Chromium's `"Lax"`.

  defstruct cookies: %{}, next_creation: 0

  @opaque t :: %__MODULE__{cookies: map(), next_creation: non_neg_integer()}

  # Fri, 31 Dec 9999 23:59:59 UTC (network.ts `kMaxCookieExpiresDateInSeconds`).
  @max_expires 253_402_300_799
  @same_site %{"strict" => "Strict", "lax" => "Lax", "none" => "None"}
  @fields [
    name: :string,
    value: :string,
    url: :string,
    domain: :string,
    path: :string,
    expires: :number,
    httpOnly: :boolean,
    secure: :boolean,
    sameSite: :same_site
  ]

  # The protocol's `SetNetworkCookie` fields. `partitionKey` and `_crHasCrossSiteAncestor`,
  # which Chromium's `cookies()` gives partitioned cookies, are accepted and ignored, so a
  # browser session's cookies round-trip. Another key raises, as PlaywrightEx raises for a
  # nested object's.
  @known_fields @fields |> Keyword.keys() |> Enum.concat([:partitionKey, :_crHasCrossSiteAncestor]) |> Enum.sort()
  @known_names Enum.map(@known_fields, &Atom.to_string/1)

  def new, do: %__MODULE__{}

  def seed_request(%__MODULE__{} = jar, %URI{} = url, %Plug.Conn{} = conn) do
    conn
    |> Plug.Conn.get_req_header("cookie")
    |> Enum.flat_map(&String.split(&1, ";", trim: true))
    |> Enum.reduce(jar, fn cookie, jar ->
      store_cookie(jar, url, String.trim(cookie) <> "; Path=/")
    end)
  end

  def store_response(%__MODULE__{} = jar, %URI{} = url, set_cookie_headers) do
    Enum.reduce(set_cookie_headers, jar, &store_cookie(&2, url, &1))
  end

  def request_header(%__MODULE__{} = jar, %URI{} = url) do
    jar
    |> live_cookies()
    |> Enum.filter(&cookie_matches_url?(&1, url))
    |> Enum.sort_by(fn cookie -> {-String.length(cookie.path), cookie.creation} end)
    |> Enum.map_join("; ", fn
      %{name: "", value: value} -> value
      cookie -> "#{cookie.name}=#{cookie.value}"
    end)
  end

  # Playwright's `browserContext.addCookies`: every cookie is checked and normalized
  # first (network.ts `rewriteCookies`), so an invalid one adds none.
  def add_cookies(%__MODULE__{} = jar, cookies) when is_list(cookies) do
    cookies |> Enum.with_index() |> Enum.each(&check_fields!/1)

    cookies
    |> Enum.map(&rewrite_cookie!/1)
    |> Enum.reduce(jar, fn cookie, jar ->
      put_cookie(jar, %{
        name: cookie.name,
        value: cookie.value,
        domain: String.downcase(cookie.domain),
        path: cookie.path,
        expires: added_expiration(cookie[:expires]),
        http_only: cookie[:httpOnly] == true,
        secure: cookie[:secure] == true,
        same_site: cookie[:sameSite] || "Lax"
      })
    end)
  end

  # `browserContext.cookies(urls)`: all cookies for no URLs (network.ts `filterCookies`).
  def cookies(%__MODULE__{} = jar, urls) when is_list(urls) do
    urls = Enum.map(urls, &parse_url!/1)

    jar
    |> live_cookies()
    |> Enum.filter(fn cookie -> urls == [] or Enum.any?(urls, &cookie_matches_url?(cookie, &1)) end)
    |> Enum.sort_by(& &1.creation)
    |> Enum.map(fn cookie ->
      %{
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain,
        path: cookie.path,
        expires: cookie.expires || -1,
        httpOnly: cookie.http_only,
        secure: cookie.secure,
        sameSite: cookie.same_site
      }
    end)
  end

  # Removes the cookies whose fields match all `filters` (`name`, `domain` or `path`: a
  # string or a `Playwright.RegExp`), or every cookie for none (network.ts `cookieMatchesClearFilter`).
  def clear_cookies(%__MODULE__{} = jar, filters) when filters == %{}, do: %{jar | cookies: %{}}

  def clear_cookies(%__MODULE__{} = jar, filters) when is_map(filters) do
    cookies =
      Map.reject(jar.cookies, fn {_key, cookie} ->
        Enum.all?(filters, fn {field, expected} ->
          Fluffy.Expect.Internal.matches?(expected, Map.fetch!(cookie, field))
        end)
      end)

    %{jar | cookies: cookies}
  end

  # PlaywrightEx's check of a nested object's keys, with its message.
  defp check_fields!({cookie, index}) when is_map(cookie) do
    for {key, _value} <- cookie, not ((is_atom(key) or is_binary(key)) and to_string(key) in @known_names) do
      raise ArgumentError,
            "browserContext.addCookies: unknown field cookies[#{index}].#{field_name(key)}, expected one of " <>
              Enum.map_join(@known_fields, ", ", &inspect/1)
    end
  end

  defp check_fields!(_cookie_and_index), do: :ok

  defp field_name(key) when is_atom(key), do: Atom.to_string(key)
  defp field_name(key), do: inspect(key)

  # network.ts `rewriteCookies`, after checking the protocol's field types.
  defp rewrite_cookie!(cookie) when is_map(cookie) do
    cookie = Map.new(cookie, fn {key, value} -> {to_string(key), value} end)

    fields =
      for {field, type} <- @fields,
          value <- [Map.get(cookie, Atom.to_string(field))],
          not is_nil(value) or field in [:name, :value],
          into: %{},
          do: {field, check_type!(field, type, value)}

    url = fields[:url]
    expires = fields[:expires]

    if not present?(url) and not (present?(fields[:domain]) and present?(fields[:path])),
      do: raise(ArgumentError, "Cookie should have a url or a domain/path pair")

    if present?(url) and present?(fields[:domain]), do: raise(ArgumentError, "Cookie should have either url or domain")
    if present?(url) and present?(fields[:path]), do: raise(ArgumentError, "Cookie should have either url or path")

    if is_number(expires) and ((expires < 0 and expires != -1) or expires > @max_expires) do
      raise ArgumentError,
            "Cookie should have a valid expires, only -1 or a positive number for the unix timestamp in seconds is allowed"
    end

    if present?(url), do: Map.merge(fields, url_fields!(url, fields.name)), else: fields
  end

  defp rewrite_cookie!(cookie), do: raise(ArgumentError, "expected a cookie map, got: #{inspect(cookie)}")

  defp url_fields!(url, name) do
    if url == "about:blank", do: raise(ArgumentError, ~s(Blank page can not have cookie "#{name}"))
    if String.starts_with?(url, "data:"), do: raise(ArgumentError, ~s(Data URL page can not have cookie "#{name}"))

    url = parse_url!(url)
    {last_slash, 1} = url.path |> :binary.matches("/") |> List.last()

    %{domain: url.host, path: binary_part(url.path, 0, last_slash + 1), secure: url.scheme == "https"}
  end

  defp check_type!(_field, :string, value) when is_binary(value), do: value
  defp check_type!(_field, :number, value) when is_number(value), do: value
  defp check_type!(_field, :boolean, value) when is_boolean(value), do: value
  defp check_type!(_field, :same_site, value) when value in ["Strict", "Lax", "None"], do: value

  defp check_type!(field, :same_site, value),
    do: raise(ArgumentError, "cookie #{field}: expected one of (Strict|Lax|None), got: #{inspect(value)}")

  defp check_type!(field, type, value),
    do: raise(ArgumentError, "cookie #{field}: expected #{type}, got: #{inspect(value)}")

  defp present?(value), do: value not in [nil, ""]

  # As JS's `new URL(url)`: a lowercase host, and a `/` path for an origin.
  defp parse_url!(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host} = uri} when is_binary(scheme) and host not in [nil, ""] ->
        %{uri | host: String.downcase(host), path: if(uri.path in [nil, ""], do: "/", else: uri.path)}

      _invalid ->
        raise ArgumentError, "Invalid URL: #{inspect(url)}"
    end
  end

  defp parse_url!(url), do: raise(ArgumentError, "expected a URL string, got: #{inspect(url)}")

  # A browser deletes a cookie added with an expiry in the past, as `clearCookies` relies on.
  defp added_expiration(expires) when expires in [nil, -1], do: nil
  defp added_expiration(expires), do: if(expires <= System.system_time(:second), do: :delete, else: expires)

  defp put_cookie(jar, %{expires: :delete} = cookie),
    do: %{jar | cookies: Map.delete(jar.cookies, {cookie.name, cookie.domain, cookie.path})}

  defp put_cookie(jar, cookie) do
    key = {cookie.name, cookie.domain, cookie.path}

    case jar.cookies[key] do
      nil ->
        cookie = Map.put(cookie, :creation, jar.next_creation)
        %{jar | cookies: Map.put(jar.cookies, key, cookie), next_creation: jar.next_creation + 1}

      existing ->
        %{jar | cookies: Map.put(jar.cookies, key, Map.put(cookie, :creation, existing.creation))}
    end
  end

  defp store_cookie(jar, url, header) do
    with {:ok, name, value, attributes} <- parse_set_cookie(header),
         {:ok, domain} <- cookie_domain(attributes, url.host) do
      put_cookie(jar, %{
        name: name,
        value: value,
        domain: domain,
        path: cookie_path(attributes, url.path),
        expires: expiration(attributes),
        http_only: Map.has_key?(attributes, "httponly"),
        secure: Map.has_key?(attributes, "secure"),
        same_site: same_site(attributes)
      })
    else
      :ignore -> jar
    end
  end

  defp parse_set_cookie(header) do
    with [name_value | raw_attributes] <- String.split(header, ";"),
         [name, value] when name != "" <- String.split(name_value, "=", parts: 2) do
      {:ok, String.trim(name), String.trim(value), Map.new(raw_attributes, &parse_attribute/1)}
    else
      _invalid ->
        :ignore
    end
  end

  defp parse_attribute(raw_attribute) do
    case raw_attribute |> String.trim() |> String.split("=", parts: 2) do
      [name, value] -> {String.downcase(name), value}
      [name] -> {String.downcase(name), true}
    end
  end

  defp same_site(%{"samesite" => value}) when is_binary(value),
    do: Map.get(@same_site, value |> String.trim() |> String.downcase(), "Lax")

  defp same_site(_attributes), do: "Lax"

  # A Domain attribute makes a domain cookie, reported with a leading dot.
  defp cookie_domain(attributes, request_host) do
    request_host = String.downcase(request_host)

    case Map.get(attributes, "domain") do
      nil ->
        {:ok, request_host}

      requested_domain ->
        domain =
          requested_domain |> String.trim() |> String.trim_leading(".") |> String.downcase()

        if request_host == domain or String.ends_with?(request_host, "." <> domain) do
          {:ok, "." <> domain}
        else
          :ignore
        end
    end
  end

  defp cookie_path(attributes, request_path) do
    case Map.get(attributes, "path") do
      <<"/", _rest::binary>> = path -> path
      _missing_or_invalid -> default_path(request_path)
    end
  end

  defp default_path(path) when path in [nil, "", "/"], do: "/"

  defp default_path(path) do
    case path |> String.split("/") |> Enum.drop(-1) |> Enum.join("/") do
      "" -> "/"
      directory -> directory
    end
  end

  defp expiration(attributes) do
    case Map.get(attributes, "max-age") do
      nil ->
        expires_at(Map.get(attributes, "expires"))

      max_age ->
        case Integer.parse(String.trim(max_age)) do
          {seconds, ""} when seconds <= 0 -> :delete
          {seconds, ""} -> System.system_time(:second) + seconds
          _invalid -> expires_at(Map.get(attributes, "expires"))
        end
    end
  end

  defp expires_at(nil), do: nil

  defp expires_at(value) do
    case :httpd_util.convert_request_date(String.to_charlist(value)) do
      {{year, month, day}, {hour, minute, second}} ->
        {:ok, expires_at} =
          DateTime.new(Date.new!(year, month, day), Time.new!(hour, minute, second))

        unix = DateTime.to_unix(expires_at)
        if unix <= System.system_time(:second), do: :delete, else: unix

      _invalid ->
        nil
    end
  rescue
    _invalid -> nil
  end

  defp live_cookies(jar) do
    now = System.system_time(:second)
    jar.cookies |> Map.values() |> Enum.reject(&(&1.expires != nil and &1.expires <= now))
  end

  # network.ts `cookieMatchesURL`: whether the cookie goes with a request to `url`.
  defp cookie_matches_url?(cookie, url) do
    host = String.downcase(url.host)

    domain_matches?(host, cookie.domain) and path_matches?(url.path || "/", cookie.path) and
      (not cookie.secure or url.scheme == "https" or local_hostname?(host))
  end

  # network.ts `domainMatches`: a domain without a leading dot is host-only.
  defp domain_matches?(host, domain),
    do: host == domain or (String.starts_with?(domain, ".") and String.ends_with?("." <> host, domain))

  # network.ts `pathMatches`, RFC 6265's path-match.
  defp path_matches?(request_path, cookie_path) do
    request_path == cookie_path or
      (String.starts_with?(request_path, cookie_path) and
         (String.ends_with?(cookie_path, "/") or binary_part(request_path, byte_size(cookie_path), 1) == "/"))
  end

  # network.ts `isLocalHostname`, Chromium's net::IsLocalhost(): localhost, *.localhost,
  # 127.0.0.0/8 and [::1], which `URI` gives without brackets.
  defp local_hostname?(host) do
    host in ["localhost", "::1"] or String.ends_with?(host, ".localhost") or
      match?({:ok, {127, _, _, _}}, :inet.parse_ipv4strict_address(String.to_charlist(host)))
  end
end
