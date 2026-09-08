defmodule Fluffy.TestHTTPFixtures do
  @moduledoc false

  use GenServer

  alias __MODULE__.Fixture

  defmodule Fixture do
    @moduledoc false

    @enforce_keys [:token, :path]
    defstruct [:token, :path]
  end

  def start_link(_options) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def register(response, options \\ []) do
    register_fixture({:repeat, response}, options)
  end

  def register_sequence(responses, options \\ []) when is_list(responses) do
    if responses == [], do: raise(ArgumentError, "response sequence cannot be empty")
    register_fixture({:sequence, responses}, options)
  end

  def requests(%Fixture{token: token}) do
    GenServer.call(__MODULE__, {:requests, token})
  end

  def registered?(%Fixture{token: token}) do
    GenServer.call(__MODULE__, {:registered?, token})
  end

  def path(%Fixture{path: base_path}, suffix \\ "") do
    append_suffix(base_path, suffix)
  end

  def url(%Fixture{} = fixture, suffix \\ "") do
    Fluffy.TestServer.base_url() <> path(fixture, suffix)
  end

  def dispatch(token, request) do
    GenServer.call(__MODULE__, {:dispatch, token, request})
  end

  @impl true
  def init(_options) do
    {:ok, %{fixtures: %{}, owner_refs: %{}, ref_owners: %{}}}
  end

  @impl true
  def handle_call({:register, owner, response}, _from, state) do
    token = state |> next_token() |> Integer.to_string(36)
    path = "/__fluffy__/case/#{token}/"
    fixture = %{owner: owner, response: response, requests: []}

    state =
      state
      |> ensure_owner_monitor(owner)
      |> put_in([:fixtures, token], fixture)

    {:reply, %Fixture{token: token, path: path}, state}
  end

  def handle_call({:requests, token}, _from, state) do
    requests =
      case Map.get(state.fixtures, token) do
        nil -> []
        fixture -> Enum.reverse(fixture.requests)
      end

    {:reply, requests, state}
  end

  def handle_call({:registered?, token}, _from, state) do
    case Map.get(state.fixtures, token) do
      %{owner: owner} when is_pid(owner) ->
        if Process.alive?(owner) do
          {:reply, true, state}
        else
          {:reply, false, remove_owner(state, owner)}
        end

      nil ->
        {:reply, false, state}
    end
  end

  def handle_call({:dispatch, token, request}, _from, state) do
    case Map.get(state.fixtures, token) do
      nil ->
        {:reply, {:error, :not_found}, state}

      fixture ->
        {handler, response_state} = take_response(fixture.response)
        fixture = %{fixture | response: response_state, requests: [request | fixture.requests]}
        {:reply, {:ok, handler}, put_in(state, [:fixtures, token], fixture)}
    end
  end

  @impl true
  def handle_info({:DOWN, reference, :process, owner, _reason}, state) do
    if state.ref_owners[reference] == owner do
      {:noreply, remove_owner(state, owner)}
    else
      {:noreply, state}
    end
  end

  defp register_fixture(response, options) do
    owner = options |> Keyword.validate!([:owner]) |> Keyword.get(:owner, self())

    if !is_pid(owner), do: raise(ArgumentError, "fixture owner must be a pid")
    GenServer.call(__MODULE__, {:register, owner, response})
  end

  defp take_response({:repeat, handler}), do: {handler, {:repeat, handler}}

  defp take_response({:sequence, [handler | rest]}) do
    next = if rest == [], do: {:exhausted, []}, else: {:sequence, rest}
    {handler, next}
  end

  defp take_response({:exhausted, []}) do
    {%{status: 410, body: "fixture response sequence exhausted"}, {:exhausted, []}}
  end

  defp ensure_owner_monitor(state, owner) do
    if Map.has_key?(state.owner_refs, owner) do
      state
    else
      reference = Process.monitor(owner)

      state
      |> put_in([:owner_refs, owner], reference)
      |> put_in([:ref_owners, reference], owner)
    end
  end

  defp remove_owner(state, owner) do
    {reference, owner_refs} = Map.pop(state.owner_refs, owner)
    if reference, do: Process.demonitor(reference, [:flush])

    fixtures =
      Map.reject(state.fixtures, fn {_token, fixture} -> fixture.owner == owner end)

    %{
      state
      | fixtures: fixtures,
        owner_refs: owner_refs,
        ref_owners: Map.delete(state.ref_owners, reference)
    }
  end

  defp next_token(state) do
    token = System.unique_integer([:positive, :monotonic])

    if Map.has_key?(state.fixtures, Integer.to_string(token, 36)),
      do: next_token(state),
      else: token
  end

  defp append_suffix(base_path, ""), do: base_path

  defp append_suffix(base_path, suffix) do
    base_path <> String.trim_leading(suffix, "/")
  end
end

defmodule Fluffy.TestHTTPFixturePlug do
  @moduledoc false

  import Plug.Conn

  alias Fluffy.TestHTTPFixtures

  def init(options), do: options

  def call(conn, _options) do
    case fixture_path(conn.request_path) do
      {:ok, token, path} -> dispatch(conn, token, path)
      :pass -> conn
    end
  end

  defp dispatch(conn, token, path) do
    {body, conn} = read_request_body(conn)

    request = %{
      method: conn.method,
      path: path,
      request_path: conn.request_path,
      query: conn.query_string,
      body: body,
      headers: conn.req_headers
    }

    case TestHTTPFixtures.dispatch(token, request) do
      {:ok, handler} -> send_fixture_response(conn, response(handler, request))
      {:error, :not_found} -> conn |> send_resp(404, "unknown HTTP fixture") |> halt()
    end
  end

  defp response(handler, request) when is_function(handler, 1), do: handler.(request)
  defp response(response, _request) when is_map(response), do: response

  defp send_fixture_response(conn, response) do
    status = Map.get(response, :status, 200)
    headers = Map.get(response, :headers, [])
    body = Map.get(response, :body, "")

    conn =
      if Enum.any?(headers, fn {name, _value} -> String.downcase(name) == "content-type" end) do
        conn
      else
        put_resp_content_type(conn, "text/html")
      end

    headers = Enum.map(headers, fn {name, value} -> {String.downcase(name), value} end)
    conn = prepend_resp_headers(conn, headers)

    conn |> send_resp(status, body) |> halt()
  end

  defp read_request_body(conn, body \\ "") do
    case read_body(conn) do
      {:ok, chunk, conn} -> {body <> chunk, conn}
      {:more, chunk, conn} -> read_request_body(conn, body <> chunk)
    end
  end

  defp fixture_path(request_path) do
    case String.split(request_path, "/", trim: false) do
      ["", "__fluffy__", "case", token | rest] when token != "" ->
        {:ok, token, "/" <> Enum.join(rest, "/")}

      _other ->
        :pass
    end
  end
end
