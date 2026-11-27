defmodule Fluffy.Dev.PlaywrightRelease do
  @moduledoc false

  @project "mix.exs"
  @lock "mix.lock"
  @oldest_lock "mix.lock.oldest"
  @consumer_lock "integration/consumer/mix.lock"
  @lock_entry ~r/^  "playwright": \{:hex, :playwright_ex, "([^"]+)"[^\n]*/m
  @requirement ~r/^([ \t]*\{:playwright, ")~> [^"]+(", hex: :playwright_ex\},)$/m

  def main(["prepare", release]) do
    File.cd!(Path.expand("..", __DIR__), fn -> prepare(version!(release)) end)
  rescue
    error ->
      IO.puts(:stderr, Exception.message(error))
      System.halt(1)
  end

  def main(_args) do
    IO.puts(:stderr, "Usage: elixir dev/playwright_release.exs prepare <version>")
    System.halt(1)
  end

  defp prepare(release) do
    originals = Map.new([@project, @lock, @oldest_lock, @consumer_lock], &{&1, File.read!(&1)})
    config = originals[@project]

    if length(Regex.scan(@requirement, config)) != 1 do
      raise "Expected one PlaywrightEx requirement in #{@project}"
    end

    lock_entry!(originals[@oldest_lock], @oldest_lock)

    try do
      # Resolve the chosen version even when Hex already has a later compatible one.
      set_requirement(config, "== #{release}")
      mix(["deps.update", "playwright"])
      mix(["deps.update", "playwright"], cd: Path.dirname(@consumer_lock))

      newest = File.read!(@lock)
      entry = check_release!(newest, @lock, release)
      check_release!(File.read!(@consumer_lock), @consumer_lock, release)

      floor = Regex.replace(@lock_entry, originals[@oldest_lock], fn _, _ -> entry end)
      set_requirement(config, "~> #{release}")
      verify_floor(floor)
      File.write!(@oldest_lock, floor)
      File.write!(@lock, newest)
    rescue
      error ->
        Enum.each(originals, fn {path, content} -> File.write!(path, content) end)
        reraise error, __STACKTRACE__
    end

    mix(["setup"])
    mix(["usage_rules.sync", "--yes"])
  end

  defp version!(value) do
    case Version.parse(value) do
      {:ok, %Version{build: nil}} -> value
      _ -> raise "Invalid PlaywrightEx version: #{inspect(value)}"
    end
  end

  defp set_requirement(config, requirement) do
    updated =
      Regex.replace(@requirement, config, fn _, before, after_requirement ->
        before <> requirement <> after_requirement
      end)

    File.write!(@project, updated)
  end

  defp lock_entry!(text, path) do
    case Regex.scan(@lock_entry, text) do
      [[entry, version]] -> {entry, version!(version)}
      _ -> raise "Expected one PlaywrightEx Hex entry in #{path}"
    end
  end

  defp check_release!(text, path, release) do
    case lock_entry!(text, path) do
      {entry, ^release} -> entry
      _ -> raise "Expected PlaywrightEx #{release} in #{path}"
    end
  end

  defp verify_floor(floor) do
    # Keep every other floor pinned and resolve the lock with empty dependencies.
    deps = Path.join(System.tmp_dir!(), "fluffy-playwright-oldest-#{Base.url_encode64(:crypto.strong_rand_bytes(12))}")
    File.mkdir!(deps)

    try do
      File.write!(@lock, floor)
      mix(["deps.get", "--check-locked"], env: [{"MIX_DEPS_PATH", deps}])

      if File.read!(@lock) != floor do
        raise "Resolving the oldest dependencies changed the floor lockfile"
      end
    after
      File.rm_rf!(deps)
    end
  end

  defp mix(args, opts \\ []) do
    env = [{"MIX_ENV", "test"} | Keyword.get(opts, :env, [])]
    opts = Keyword.merge(opts, env: env, into: IO.stream(:stdio, :line))

    case System.cmd("mix", args, opts) do
      {_, 0} -> :ok
      {_, status} -> raise "mix #{Enum.join(args, " ")} failed (exit #{status})"
    end
  end
end

Fluffy.Dev.PlaywrightRelease.main(System.argv())
