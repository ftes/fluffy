defmodule Fluffy.Consumer do
  @moduledoc false

  @root Path.expand("..", __DIR__)
  @integration_dir __DIR__
  @target Path.join(@integration_dir, "consumer")
  @fixture_dir Path.join(@integration_dir, "consumer_fixture")
  @staging Path.join(
             @integration_dir,
             ".consumer-build-#{System.unique_integer([:positive, :monotonic])}"
           )

  def generate! do
    archives = Path.join(@staging <> "-tools", "archives")

    try do
      File.mkdir_p!(archives)
      link_installed_archives!(archives)
      install_generators!(archives)
      phx_new!(archives)
      customize!(archives)
      verify!(archives)
      discard_build_artifacts!()
      replace_target!()
    after
      File.rm_rf!(@staging)
      File.rm_rf!(@staging <> "-tools")
    end
  end

  defp link_installed_archives!(destination) do
    :archives
    |> Mix.path_for()
    |> File.ls!()
    |> Enum.each(fn archive ->
      source = Path.join(Mix.path_for(:archives), archive)
      File.ln_s!(source, Path.join(destination, archive))
    end)
  end

  defp install_generators!(archives) do
    run!("mix", ["archive.install", "hex", "phx_new", "--force"], env: [{"MIX_ARCHIVES", archives}])
    run!("mix", ["archive.install", "hex", "igniter_new", "--force"], env: [{"MIX_ARCHIVES", archives}])
  end

  defp phx_new!(archives) do
    run!(
      "mix",
      [
        "igniter.new",
        @staging,
        "--with",
        "phx.new",
        "--with-args",
        "--app fluffy_consumer --module FluffyConsumer --no-ecto --no-assets --no-live " <>
          "--no-dashboard --no-mailer --no-gettext --no-install --no-agents-md",
        "--yes",
        "--no-git"
      ],
      env: [{"MIX_ARCHIVES", archives}]
    )

    File.rm_rf!(Path.join(@staging, ".git"))
  end

  defp customize!(archives) do
    env = [{"MIX_ARCHIVES", archives}]

    run!("mix", ["run", Path.join(@fixture_dir, "patch.exs")],
      cd: @staging,
      env: env
    )
  end

  defp verify!(archives) do
    run!("mix", ["deps.get"], cd: @staging, env: [{"MIX_ARCHIVES", archives}])
    run!("mix", ["test"], cd: @staging, env: [{"MIX_ARCHIVES", archives}])
  end

  defp discard_build_artifacts! do
    File.rm_rf!(Path.join(@staging, "_build"))
    File.rm_rf!(Path.join(@staging, "deps"))
  end

  defp replace_target! do
    backup = @target <> ".previous"
    File.rm_rf!(backup)

    case File.rename(@target, backup) do
      :ok ->
        case File.rename(@staging, @target) do
          :ok -> File.rm_rf!(backup)
          {:error, reason} -> restore_target!(backup, reason)
        end

      {:error, :enoent} ->
        File.rename!(@staging, @target)

      {:error, reason} ->
        raise File.Error, reason: reason, action: "back up", path: @target
    end
  end

  defp restore_target!(backup, replacement_error) do
    case File.rename(backup, @target) do
      :ok ->
        raise File.Error,
          reason: replacement_error,
          action: "replace",
          path: @target

      {:error, restoration_error} ->
        raise "failed to replace #{@target} (#{inspect(replacement_error)}) and restore " <>
                "#{backup} (#{inspect(restoration_error)})"
    end
  end

  defp run!(command, arguments, options) do
    options = Keyword.merge([cd: @root, into: IO.stream()], options)

    case System.cmd(command, arguments, options) do
      {_output, 0} -> :ok
      {_output, status} -> raise "#{command} exited with status #{status}"
    end
  end
end

Fluffy.Consumer.generate!()
