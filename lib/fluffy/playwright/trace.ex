defmodule Fluffy.Playwright.Trace do
  @moduledoc false

  alias Fluffy.TestScope
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Tracing

  @enforce_keys [:open?, :path, :tracing]
  defstruct [:open?, :path, :tracing]

  @opaque t :: %__MODULE__{
            open?: boolean(),
            path: String.t(),
            tracing: Tracing.t()
          }

  def start(context, options, capture_options) when is_map(context) do
    scope = context.resource_scope

    if !is_pid(scope) do
      raise ArgumentError, "Playwright tracing requires a session owned by Fluffy.TestScope"
    end

    metadata = TestScope.metadata(scope)
    title = Keyword.get(options, :name) || default_title(metadata)
    directory = Keyword.get(options, :directory, configured_directory())
    File.mkdir_p!(directory)
    tracing = BrowserContext.tracing(context.browser_context)

    # Starting also opens the first chunk, which `stop/1` saves.
    _disposable = Tracing.start!(tracing, Keyword.put(capture_options, :title, title))

    %__MODULE__{
      open?: Keyword.fetch!(options, :open),
      path: trace_path(directory, title),
      tracing: tracing
    }
  end

  # As in Playwright, stopping has no timeout. It runs while the session shuts down.
  def stop(%__MODULE__{} = trace) do
    saved? =
      try do
        Tracing.stop_chunk(trace.tracing, path: trace.path) == :ok
      after
        Tracing.stop(trace.tracing)
      end

    if saved? and trace.open?, do: open(trace)
    :ok
  end

  def public_state(%__MODULE__{path: path}), do: %{path: path}

  defp open(trace) do
    path = Path.absname(trace.path)
    {program, prefix} = PlaywrightEx.Driver.executable(Keyword.take(config(), [:executable]))

    spawn(fn ->
      System.cmd(program, prefix ++ ["show-trace", path], env: PlaywrightEx.Driver.driver_env(), stderr_to_stdout: true)
    end)

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

  defp configured_directory, do: Keyword.fetch!(config(), :trace_dir)

  defp config, do: Fluffy.Options.playwright_config()
end
