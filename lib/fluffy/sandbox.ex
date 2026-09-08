defmodule Fluffy.Sandbox do
  @moduledoc """
  Integrates Ecto SQL sandbox ownership with a Fluffy test scope.
  """

  alias Ecto.Adapters.SQL.Sandbox

  @default_header "x-fluffy-sandbox"
  @default_sandbox Sandbox
  @config_keys [:header, :sandbox]

  @type allowance :: module() | {module(), atom(), list()}

  @doc "Returns the HTTP header used to transport encoded sandbox metadata."
  @spec header() :: String.t()
  def header, do: config()[:header]

  @doc "Returns the sandbox allowance module or MFA used by Phoenix Ecto."
  @spec allowance() :: allowance()
  def allowance, do: config()[:sandbox]

  @doc "Returns the Phoenix socket connect-info key required by the configured header."
  @spec connect_info() :: :user_agent | :x_headers
  def connect_info do
    if header() == "user-agent", do: :user_agent, else: :x_headers
  end

  @doc false
  @spec config() :: [header: String.t(), sandbox: allowance()]
  def config do
    :fluffy
    |> Application.get_env(__MODULE__, [])
    |> validate_config!()
  end

  @doc false
  def validate_config!(options) when is_list(options) do
    options = Keyword.validate!(options, @config_keys)
    header = Keyword.get(options, :header, @default_header)
    sandbox = Keyword.get(options, :sandbox, @default_sandbox)

    validate_header!(header)
    validate_sandbox!(sandbox)

    [header: header, sandbox: sandbox]
  end

  def validate_config!(other) do
    raise ArgumentError,
          "expected :fluffy, Fluffy.Sandbox configuration to be a keyword list, got: #{inspect(other)}"
  end

  if Code.ensure_loaded?(Sandbox) and
       Code.ensure_loaded?(Phoenix.Ecto.SQL.Sandbox) do
    import Phoenix.LiveView, only: [connected?: 1, get_connect_info: 2]

    alias Phoenix.Ecto.SQL.Sandbox, as: PhoenixSandbox
    alias Sandbox, as: EctoSandbox

    @doc false
    def acquire(context, repos) when is_map(context) and is_list(repos) do
      async? = Map.get(context, :async, false)

      owners =
        repos
        |> Enum.map(&ensure_owner(&1, async?))
        |> Enum.reject(&is_nil/1)

      metadata =
        repos
        |> PhoenixSandbox.metadata_for(self())
        |> PhoenixSandbox.encode_metadata()

      {owners, {header(), metadata}}
    end

    def on_mount(:default, _params, _session, socket) do
      if connected?(socket) do
        metadata = sandbox_metadata(socket)

        PhoenixSandbox.allow(metadata, allowance())
      end

      {:cont, socket}
    end

    defp ensure_owner(repo, async?) do
      case EctoSandbox.checkout(repo) do
        :ok ->
          :ok = EctoSandbox.checkin(repo)

          case EctoSandbox.mode(repo, {:shared, self()}) do
            :already_shared ->
              nil

            :ok ->
              :ok = EctoSandbox.mode(repo, :manual)
              EctoSandbox.start_owner!(repo, shared: not async?)

            result when result in [:not_found, :not_owner] ->
              EctoSandbox.start_owner!(repo, shared: not async?)
          end

        {:already, ownership} when ownership in [:owner, :allowed] ->
          nil
      end
    end

    defp sandbox_metadata(socket) do
      case connect_info() do
        :user_agent ->
          get_connect_info(socket, :user_agent)

        :x_headers ->
          header = header()

          socket
          |> get_connect_info(:x_headers)
          |> List.wrap()
          |> Enum.find_value(fn
            {^header, value} -> value
            _header -> nil
          end)
      end
    end
  else
    def acquire(_context, _repos) do
      raise "Fluffy.Sandbox requires the optional :ecto_sql and :phoenix_ecto dependencies"
    end

    def on_mount(:default, _params, _session, _socket) do
      raise "Fluffy.Sandbox requires the optional :ecto_sql and :phoenix_ecto dependencies"
    end
  end

  defp validate_header!(header) when is_binary(header) do
    if header == "" or header != String.downcase(header) or
         not Regex.match?(~r/^[!#$%&'*+.^_`|~0-9a-z-]+$/, header) do
      raise ArgumentError,
            "expected Fluffy sandbox :header to be a lowercase HTTP header name, got: #{inspect(header)}"
    end

    :ok
  end

  defp validate_header!(header) do
    raise ArgumentError,
          "expected Fluffy sandbox :header to be a lowercase HTTP header name, got: #{inspect(header)}"
  end

  defp validate_sandbox!(sandbox) when is_atom(sandbox), do: :ok

  defp validate_sandbox!({module, function, arguments}) when is_atom(module) and is_atom(function) and is_list(arguments),
    do: :ok

  defp validate_sandbox!(sandbox) do
    raise ArgumentError,
          "expected Fluffy sandbox :sandbox to be a module or {module, function, arguments} MFA, got: #{inspect(sandbox)}"
  end
end
