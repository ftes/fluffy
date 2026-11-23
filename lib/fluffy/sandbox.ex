defmodule Fluffy.Sandbox do
  @moduledoc """
  Carries the test's Ecto SQL sandbox to browser sessions. The sandbox owner is the
  application's, started by its DataCase or ConnCase.

  A test with browser sessions waits, after they close and before the owner stops, for the
  LiveViews the hook allowed to exit, up to 5 seconds, so their `terminate/2` still reaches the
  database.

  See [Ecto sandbox](installation.md#ecto-sandbox) for setup.
  """

  alias Ecto.Adapters.SQL.Sandbox
  alias Fluffy.Deadline

  @default_header "x-fluffy-sandbox"
  @default_sandbox Sandbox
  @config_keys [:header, :sandbox, :trap_exit]
  @registry __MODULE__.Registry
  # LiveViewTest's budget for a LiveView to shut down.
  @exit_timeout 5_000

  @type allowance :: module() | {module(), atom(), list()}

  @doc "Returns the HTTP header used to transport encoded sandbox metadata."
  @spec header() :: String.t()
  def header, do: config()[:header]

  @doc "Returns the sandbox allowance module or MFA used by Phoenix Ecto and `allow/3`."
  @spec allowance() :: allowance()
  def allowance, do: config()[:sandbox]

  @doc "Returns the Phoenix socket connect-info key required by the configured header."
  @spec connect_info() :: :user_agent | :x_headers
  def connect_info do
    if header() == "user-agent", do: :user_agent, else: :x_headers
  end

  @doc """
  The sandbox callback Phoenix Ecto calls when a hook passes `Fluffy.Sandbox` to
  `Phoenix.Ecto.SQL.Sandbox.allow/2`; tests don't call it. It allows `child` through the
  configured `:sandbox` and has `owner`'s test wait for the calling process to exit. Only a
  custom LiveView hook needs it, see [Ecto sandbox](installation.md#ecto-sandbox).
  """
  @spec allow(module(), pid(), pid()) :: term()
  def allow(repo, owner, child) do
    # Once per process, though Phoenix Ecto allows each repo.
    if owner not in Registry.keys(@registry, self()), do: Registry.register(@registry, owner, nil)

    case allowance() do
      {module, function, arguments} -> apply(module, function, [repo, owner, child | arguments])
      module -> module.allow(repo, owner, child)
    end
  end

  @doc false
  # Has the test wait, before its sandbox owners stop, for the processes `allow/3` registered
  # for `owner` to exit. Registered once per test, before the first session's own `on_exit`:
  # ExUnit runs them in reverse, so it runs once all the test's sessions are closed. A process
  # still running at the deadline is left to stop with the owner.
  @spec await_exits_on_exit(pid()) :: :ok
  def await_exits_on_exit(owner) do
    if owner == self() and Process.put({__MODULE__, :await_exits}, true) == nil,
      do: ExUnit.Callbacks.on_exit(fn -> await_exits(owner) end)

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp await_exits(owner) do
    deadline = Deadline.new(@exit_timeout)

    for {pid, nil} <- Registry.lookup(@registry, owner) do
      monitor = Process.monitor(pid)

      receive do
        {:DOWN, ^monitor, :process, _pid, _reason} -> :ok
      after
        Deadline.remaining(deadline) -> Process.demonitor(monitor, [:flush])
      end
    end

    :ok
  end

  @doc false
  # The header that lets a browser session's requests and LiveViews use `owner`'s sandbox
  # connections, for the configured `ecto_repos`; nil without any.
  @spec metadata_header(pid()) :: {String.t(), String.t()} | nil
  def metadata_header(owner) when is_pid(owner) do
    case Application.get_env(:fluffy, :ecto_repos, []) do
      [] -> nil
      repos -> {header(), encode_metadata(repos, owner)}
    end
  end

  @doc false
  @spec config() :: [header: String.t(), sandbox: allowance(), trap_exit: boolean()]
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

    trap_exit? = Keyword.get(options, :trap_exit, true)

    if not is_boolean(trap_exit?) do
      raise ArgumentError,
            "invalid config :fluffy, Fluffy.Sandbox: expected :trap_exit to be a boolean, got: #{inspect(trap_exit?)}"
    end

    validate_header!(header)
    validate_sandbox!(sandbox)

    [header: header, sandbox: sandbox, trap_exit: trap_exit?]
  end

  def validate_config!(other) do
    raise ArgumentError,
          "invalid config :fluffy, Fluffy.Sandbox: expected a keyword list, got: #{inspect(other)}"
  end

  if Code.ensure_loaded?(Sandbox) and
       Code.ensure_loaded?(Phoenix.Ecto.SQL.Sandbox) do
    import Phoenix.LiveView, only: [connected?: 1, get_connect_info: 2]

    alias Phoenix.Ecto.SQL.Sandbox, as: PhoenixSandbox

    defp encode_metadata(repos, owner) do
      repos
      |> PhoenixSandbox.metadata_for(owner, trap_exit: config()[:trap_exit])
      |> PhoenixSandbox.encode_metadata()
    end

    @doc "LiveView `on_mount` hook that allows a connected LiveView to use the test's sandbox connection, with `allow/3`."
    def on_mount(:default, _params, _session, socket) do
      if connected?(socket) do
        metadata = sandbox_metadata(socket)

        PhoenixSandbox.allow(metadata, __MODULE__)
      end

      {:cont, socket}
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
    defp encode_metadata(_repos, _owner) do
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
            "invalid config :fluffy, Fluffy.Sandbox: expected :header to be a lowercase HTTP header name, got: #{inspect(header)}"
    end

    :ok
  end

  defp validate_header!(header) do
    raise ArgumentError,
          "invalid config :fluffy, Fluffy.Sandbox: expected :header to be a lowercase HTTP header name, got: #{inspect(header)}"
  end

  # `allow/3` delegates to the configured sandbox, so this one would call itself.
  defp validate_sandbox!(sandbox) when sandbox == __MODULE__ or (is_tuple(sandbox) and elem(sandbox, 0) == __MODULE__) do
    raise ArgumentError,
          "invalid config :fluffy, Fluffy.Sandbox: :sandbox can't be Fluffy.Sandbox; pass Fluffy.Sandbox to Phoenix.Ecto.SQL.Sandbox.allow/2 in your hook instead"
  end

  defp validate_sandbox!(sandbox) when is_atom(sandbox), do: :ok

  defp validate_sandbox!({module, function, arguments}) when is_atom(module) and is_atom(function) and is_list(arguments),
    do: :ok

  defp validate_sandbox!(sandbox) do
    raise ArgumentError,
          "invalid config :fluffy, Fluffy.Sandbox: expected :sandbox to be a module or {module, function, arguments} MFA, got: #{inspect(sandbox)}"
  end
end
