defmodule Fluffy.CookieJar do
  @moduledoc false

  defstruct cookies: %{}, next_creation: 0

  @opaque t :: %__MODULE__{cookies: map(), next_creation: non_neg_integer()}

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
    jar.cookies
    |> Map.values()
    |> Enum.filter(&(not expired_cookie?(&1) and cookie_matches?(&1, url)))
    |> Enum.sort_by(fn cookie -> {-String.length(cookie.path), cookie.creation} end)
    |> Enum.map_join("; ", &"#{&1.name}=#{&1.value}")
  end

  defp store_cookie(jar, url, header) do
    with {:ok, name, value, attributes} <- parse_set_cookie(header),
         {:ok, domain, host_only?} <- cookie_domain(attributes, url.host) do
      path = cookie_path(attributes, url.path)
      key = {name, domain, path}
      expiration = expiration(attributes)

      if expiration == :delete do
        %{jar | cookies: Map.delete(jar.cookies, key)}
      else
        creation =
          case jar.cookies[key] do
            nil -> jar.next_creation
            cookie -> cookie.creation
          end

        cookie = %{
          name: name,
          value: value,
          domain: domain,
          host_only?: host_only?,
          path: path,
          secure?: Map.has_key?(attributes, "secure"),
          expires_at: expiration,
          creation: creation
        }

        next_creation =
          if Map.has_key?(jar.cookies, key), do: jar.next_creation, else: creation + 1

        %{jar | cookies: Map.put(jar.cookies, key, cookie), next_creation: next_creation}
      end
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

  defp cookie_domain(attributes, request_host) do
    case Map.get(attributes, "domain") do
      nil ->
        {:ok, String.downcase(request_host), true}

      requested_domain ->
        domain =
          requested_domain |> String.trim() |> String.trim_leading(".") |> String.downcase()

        if domain_match?(String.downcase(request_host), domain) do
          {:ok, domain, false}
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

  defp expired_cookie?(%{expires_at: nil}), do: false
  defp expired_cookie?(cookie), do: cookie.expires_at <= System.system_time(:second)

  defp cookie_matches?(cookie, url) do
    host = String.downcase(url.host)

    domain? =
      if cookie.host_only?, do: host == cookie.domain, else: domain_match?(host, cookie.domain)

    domain? and path_match?(url.path || "/", cookie.path) and
      (not cookie.secure? or secure_cookie_origin?(url))
  end

  defp secure_cookie_origin?(%URI{scheme: "https"}), do: true

  defp secure_cookie_origin?(%URI{host: host}) when is_binary(host) do
    host = String.downcase(host)
    localhost? = host == "localhost" or String.ends_with?(host, ".localhost")

    loopback? =
      case :inet.parse_address(String.to_charlist(host)) do
        {:ok, {127, _second, _third, _fourth}} -> true
        {:ok, {0, 0, 0, 0, 0, 0, 0, 1}} -> true
        _other -> false
      end

    localhost? or loopback?
  end

  defp secure_cookie_origin?(_url), do: false

  defp domain_match?(host, domain) do
    host == domain or String.ends_with?(host, "." <> domain)
  end

  defp path_match?(request_path, cookie_path) do
    request_path == cookie_path or
      (String.starts_with?(request_path, cookie_path) and
         (String.ends_with?(cookie_path, "/") or
            String.at(request_path, String.length(cookie_path)) == "/"))
  end
end
