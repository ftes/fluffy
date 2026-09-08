defmodule Fluffy.Playwright.Trace do
  @moduledoc false

  alias Fluffy.TestScope
  alias PlaywrightEx.Tracing

  @enforce_keys [:connection, :executable, :open?, :path, :timeout, :tracing_id]
  defstruct [:connection, :executable, :open?, :path, :timeout, :tracing_id]

  @opaque t :: %__MODULE__{
            connection: GenServer.name(),
            executable: String.t(),
            open?: boolean(),
            path: String.t(),
            timeout: timeout(),
            tracing_id: String.t()
          }

  def start(context, options) when is_map(context) do
    scope = context.resource_scope

    if !is_pid(scope) do
      raise ArgumentError, "Playwright tracing requires a session owned by Fluffy.TestScope"
    end

    metadata = TestScope.metadata(scope)
    title = Keyword.get(options, :name) || default_title(metadata)
    directory = Keyword.get(options, :directory, configured_directory())
    path = trace_path(directory, title)
    File.mkdir_p!(directory)

    tracing_options = [
      connection: context.connection,
      timeout: context.timeout,
      title: title,
      screenshots: Keyword.fetch!(options, :screenshots),
      snapshots: Keyword.fetch!(options, :snapshots),
      sources: Keyword.fetch!(options, :sources)
    ]

    case Tracing.tracing_start(context.tracing_id, tracing_options) do
      {:ok, _result} -> :ok
      {:error, error} -> raise "Could not start Playwright tracing: #{inspect(error)}"
    end

    case Tracing.tracing_start_chunk(context.tracing_id,
           connection: context.connection,
           timeout: context.timeout,
           title: title
         ) do
      {:ok, _result} ->
        %__MODULE__{
          connection: context.connection,
          executable: configured_executable(),
          open?: Keyword.fetch!(options, :open),
          path: path,
          timeout: context.timeout,
          tracing_id: context.tracing_id
        }

      {:error, error} ->
        Tracing.tracing_stop(context.tracing_id,
          connection: context.connection,
          timeout: context.timeout
        )

        raise "Could not start Playwright trace chunk: #{inspect(error)}"
    end
  end

  def stop(%__MODULE__{} = trace) do
    saved? =
      try do
        save_chunk(trace)
      after
        Tracing.tracing_stop(trace.tracing_id,
          connection: trace.connection,
          timeout: trace.timeout
        )
      end

    if saved? and trace.open?, do: open(trace)
    :ok
  end

  def public_state(%__MODULE__{path: path}), do: %{path: path}

  defp save_chunk(trace) do
    case Tracing.tracing_stop_chunk(trace.tracing_id,
           connection: trace.connection,
           timeout: trace.timeout
         ) do
      {:ok, artifact} ->
        case File.cp(artifact.absolute_path, trace.path) do
          :ok -> true
          {:error, _reason} -> false
        end

      {:error, _reason} ->
        false
    end
  end

  defp open(trace) do
    path = Path.absname(trace.path)
    spawn(fn -> System.cmd(trace.executable, ["show-trace", path], stderr_to_stdout: true) end)
    :ok
  end

  defp trace_path(directory, title) do
    unique = System.unique_integer([:positive, :monotonic])
    Path.join(directory, "#{slug(title)}-#{unique}.zip")
  end

  defp default_title(context) do
    module = context |> Map.get(:module, Fluffy) |> inspect()
    test = Map.get(context, :test, "trace")
    "#{module} #{test}"
  end

  defp slug(title) do
    title
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1-\\2")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "trace"
      slug -> slug
    end
  end

  defp configured_directory do
    :fluffy
    |> Application.fetch_env!(:playwright)
    |> Keyword.get(:trace_dir, "traces")
  end

  defp configured_executable do
    :fluffy
    |> Application.fetch_env!(:playwright)
    |> Keyword.fetch!(:executable)
  end
end
