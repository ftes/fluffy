# This repo's settings for ftes/ci's release script (scripts/release fetches it); its header
# documents each key.
defmodule ReleaseScript.Config do
  @moduledoc false

  def config do
    %{
      repo: "ftes/fluffy",
      # `RELEASE_REMOTE` names another remote than origin.
      remote: System.get_env("RELEASE_REMOTE", "origin"),
      branch: "main",
      # Its publish job releases a pushed `v*` tag once the tests passed.
      workflow: "ci.yml",
      hex_package: "fluffy",
      # Not docs/upgrading.md: its `~> 0.9.0` is the guide's target, not the latest release.
      snippets: [{"docs/installation.md", ~r/\{:fluffy, "~> ([^"]+)"/}],
      driver_line: false,
      driver_minor: false,
      minor_requirement: true,
      changelog: %{
        unreleased: "## Unreleased",
        version_prefix: "## ",
        version_suffix: "",
        date_separator: " — ",
        # Unreleased gathers every change since the last final release.
        reopen_prereleases: true,
        rc_only: "**RC only:**"
      }
    }
  end
end
