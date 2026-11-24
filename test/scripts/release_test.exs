Code.require_file("../../scripts/release.exs", __DIR__)

defmodule ReleaseScript.EditTest do
  # The release script's edits with Fluffy's config (scripts/release.exs, a copy of
  # playwright_ex's). Not on the real CHANGELOG.md: CI runs on the release commit, whose
  # changelog has no Unreleased heading.
  use ExUnit.Case, async: true

  alias ReleaseScript.Config
  alias ReleaseScript.Edit
  alias ReleaseScript.Error

  @changelog """
  # Changelog for v0.9

  Fluffy 0.9 guards the trapdoor more closely.

  ## Guarding the trapdoor

  Fluffy sleeps when music plays.

  ## Unreleased

  Changes since 0.8.0.

  ### Fixed

  - Fluffy wakes when the harp stops.

  ## 0.8.0 — 2026-11-04

  ### Added

  - A third head.
  """

  @date ~D[2026-11-24]

  # Functions, not attributes: the config holds regexes, which OTP 28 can't store in one.
  defp config, do: Config.config()
  defp cl, do: config().changelog
  defp snippet, do: config().snippets |> hd() |> elem(1)

  describe "release_heading/4" do
    test "renames Unreleased to the version and date" do
      assert Edit.release_heading(@changelog, cl(), "0.9.0-rc.6", @date) ==
               String.replace(@changelog, "## Unreleased", "## 0.9.0-rc.6 — 2026-11-24")
    end

    test "fails without an Unreleased heading" do
      assert_raise Error, ~r/no `## Unreleased` heading/, fn ->
        Edit.release_heading("# Changelog\n", cl(), "1.0.0", @date)
      end
    end
  end

  describe "start_next/3" do
    test "renames a prerelease's heading back to Unreleased" do
      released = Edit.release_heading(@changelog, cl(), "0.9.0-rc.6", @date)

      assert Edit.start_next(released, cl(), "0.9.0-rc.6") == @changelog
    end

    test "inserts an empty Unreleased above a final release" do
      released = Edit.release_heading(@changelog, cl(), "0.9.0", @date)

      assert Edit.start_next(released, cl(), "0.9.0") ==
               String.replace(@changelog, "## Unreleased", "## Unreleased\n\n## 0.9.0 — 2026-11-24")
    end

    test "inserts an empty Unreleased above a prerelease without reopen_prereleases" do
      cl = %{cl() | reopen_prereleases: false}
      released = Edit.release_heading(@changelog, cl, "0.9.0-rc.6", @date)

      assert Edit.start_next(released, cl, "0.9.0-rc.6") ==
               String.replace(@changelog, "## Unreleased", "## Unreleased\n\n## 0.9.0-rc.6 — 2026-11-24")
    end

    test "finds the version's own heading, not a prerelease's" do
      changelog = String.replace(@changelog, "## 0.8.0 — 2026-11-04", "## 0.9.0-rc.6 — 2026-11-23")
      released = Edit.release_heading(changelog, cl(), "0.9.0", @date)

      assert Edit.start_next(released, cl(), "0.9.0") =~
               "## Unreleased\n\n## 0.9.0 — 2026-11-24\n\nChanges since 0.8.0."
    end
  end

  describe "snippets and @version" do
    test "bump/3 bumps the install line and leaves other dependencies alone" do
      installation = """
      -    {:lazy_html, ">= 0.1.0", only: :test},
      +    {:lazy_html, ">= 0.1.0", only: [:dev, :test]},
      +    {:fluffy, "~> 0.9.0-rc.5", only: [:dev, :test]}
      """

      assert Edit.bump(installation, snippet(), "0.9.0-rc.6") ==
               String.replace(installation, "0.9.0-rc.5", "0.9.0-rc.6")
    end

    test "every configured snippet matches its file" do
      for {path, regex} <- config().snippets do
        assert Edit.bump_snippet(path, File.read!(path), regex, "9.9.9") =~ ~s("~> 9.9.9")
      end
    end

    test "bump_snippet/4 names the file whose snippet is gone" do
      assert_raise Error, ~r/^docs\/installation.md: no match for .* \(the release config's snippets\)$/, fn ->
        Edit.bump_snippet("docs/installation.md", "Depend on `:fluffy`.", snippet(), "0.9.0")
      end
    end

    test "requirement/2 takes major.minor.0 for a final version, the full one for a prerelease" do
      minor? = config().minor_requirement

      assert Edit.requirement("0.9.0-rc.6", minor?) == "0.9.0-rc.6"
      assert Edit.requirement("0.9.0", minor?) == "0.9.0"
      assert Edit.requirement("0.9.1", minor?) == "0.9.0"
    end

    test "reads and sets @version in mix.exs" do
      mix_exs = File.read!("mix.exs")
      current = Edit.current_version(mix_exs)

      assert Edit.set_version(mix_exs, "9.9.9") ==
               String.replace(mix_exs, ~s(@version "#{current}"), ~s(@version "9.9.9"))
    end
  end

  describe "guards" do
    test "unreleased_content?/2" do
      assert Edit.unreleased_content?(@changelog, cl())
      refute Edit.unreleased_content?("## Unreleased\n\n  \n## 0.8.0 — 2026-11-04\n\n- A third head.\n", cl())
    end

    test "newer?/2 compares SemVer, prereleases first" do
      assert Edit.newer?("0.9.0-rc.6", "0.9.0-rc.5")
      assert Edit.newer?("0.9.0-rc.10", "0.9.0-rc.9")
      assert Edit.newer?("0.9.0", "0.9.0-rc.6")
      refute Edit.newer?("0.9.0-rc.5", "0.9.0-rc.5")
    end

    test "rc_sections?/3 finds a final version's prerelease sections" do
      changelog = String.replace(@changelog, "## 0.8.0 — 2026-11-04", "## 0.9.0-rc.6 — 2026-11-23")

      assert Edit.rc_sections?(changelog, cl(), "0.9.0")
      refute Edit.rc_sections?(changelog, cl(), "0.9.0-rc.7")
      refute Edit.rc_sections?(@changelog, cl(), "0.9.0")
    end

    test "rc_only_entries?/3 finds RC-only entries in a final version's Unreleased" do
      changelog = String.replace(@changelog, "- Fluffy wakes", "- **RC only:** Fluffy wakes")

      assert Edit.rc_only_entries?(changelog, cl(), "0.9.0")
      refute Edit.rc_only_entries?(changelog, cl(), "0.9.0-rc.6")
      refute Edit.rc_only_entries?(@changelog, cl(), "0.9.0")
    end

    test "parse_version/1 takes SemVer only" do
      assert Edit.parse_version("0.9.0-rc.6") == "0.9.0-rc.6"
      assert_raise Error, ~r/not a SemVer version/, fn -> Edit.parse_version("v0.9.0") end
      assert_raise Error, ~r/not a SemVer version/, fn -> Edit.parse_version("0.9") end
      assert_raise Error, ~r/not a SemVer version/, fn -> Edit.parse_version("0.9.0+build.1") end
    end
  end
end
