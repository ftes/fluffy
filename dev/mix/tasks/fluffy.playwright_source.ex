defmodule Mix.Tasks.Fluffy.PlaywrightSource do
  @shortdoc "Fetches the Playwright source of the driver version PlaywrightEx pins"
  @moduledoc """
  Clones Playwright's source at the tag of the pinned driver (`v<version>`, see
  `PlaywrightEx.Driver.version/0`) into `tmp/playwright-<version>`, unless that exists. The
  clone is shallow, blobless and sparse: the client, server, injected and test runner sources
  (with the `expect` matchers), the protocol, the page and library tests and the API docs.

      mix fluffy.playwright_source
  """
  use Mix.Task

  @repo "https://github.com/microsoft/playwright"

  @paths ~w(
    packages/playwright-core/src packages/playwright/src packages/injected/src packages/protocol
    packages/isomorphic packages/utils tests/page tests/library docs/src/api
  )

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("loadpaths")
    version = PlaywrightEx.Driver.version()
    dir = "tmp/playwright-#{version}"

    if !File.dir?(dir) do
      # Into a temporary directory first, so an interrupted clone isn't skipped next time.
      partial = dir <> ".partial"
      File.rm_rf!(partial)
      git!(["clone", "--depth", "1", "--filter=blob:none", "--sparse", "--branch", "v#{version}", @repo, partial])
      git!(["-C", partial, "sparse-checkout", "set" | @paths])
      File.rename!(partial, dir)
    end

    Mix.shell().info("Playwright #{version} source is in #{dir}")
  end

  defp git!(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> Mix.raise("git #{Enum.join(args, " ")} exited with #{status}:\n#{output}")
    end
  end
end
