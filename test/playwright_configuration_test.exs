defmodule Fluffy.PlaywrightConfigurationTest do
  # Changes Fluffy's and Playwright's global config.
  use ExUnit.Case, async: false

  alias Fluffy.Options
  alias Fluffy.Timeouts

  @keys [
    :timeout,
    :playwright,
    :action_timeout,
    :navigation_timeout,
    :expect_timeout,
    :test_id_attribute,
    :base_url,
    :phoenix_backend_timeout,
    :expect_timout,
    :file_input_max_bytes,
    Fluffy.Sanbox
  ]

  setup do
    originals = for key <- @keys, do: {key, Application.fetch_env(:fluffy, key)}
    Enum.each(@keys, &Application.delete_env(:fluffy, &1))
    playwright = for key <- [:test, :expect], do: {key, Application.fetch_env(:playwright, key)}
    Enum.each([:test, :expect], &Application.delete_env(:playwright, &1))

    on_exit(fn ->
      for {key, original} <- originals do
        case original do
          {:ok, value} -> Application.put_env(:fluffy, key, value)
          :error -> Application.delete_env(:fluffy, key)
        end
      end

      for {key, original} <- playwright do
        case original do
          {:ok, value} -> Application.put_env(:playwright, key, value)
          :error -> Application.delete_env(:playwright, key)
        end
      end
    end)
  end

  test "rejects Fluffy's removed timeout config with the keys to use instead" do
    put_env(timeout: 2_000)

    assert_raise ArgumentError,
                 ~r/config :fluffy, timeout: is removed.*`config :playwright, :expect, timeout: \.\.\.`.*:test, action_timeout.*phoenix_backend_timeout/,
                 &Options.config!/0

    Application.delete_env(:fluffy, :timeout)

    put_env(playwright: [timeout: 15_000])

    assert_raise ArgumentError,
                 ~r/config :fluffy, playwright: is removed.*`config :playwright, :test` instead, with `action_timeout:`.*`browser_name:` for `engine:`.*`log_browser_console:`.*Event.console\(\)/,
                 &Options.config!/0

    put_env(playwright: false)
    assert_raise ArgumentError, ~r/config :fluffy, playwright: is removed/, &Options.config!/0
  end

  # Kept, a misspelt key would silently do nothing.
  test "rejects unknown keys and the config of modules that don't exist" do
    put_env(expect_timout: 1_000)
    assert_raise ArgumentError, ~r/invalid config :fluffy: unknown options \[:expect_timout\]/, &Options.config!/0
    Application.delete_env(:fluffy, :expect_timout)

    put_env([{Fluffy.Sanbox, [header: "user-agent"]}])
    assert_raise ArgumentError, ~r/invalid config :fluffy, Fluffy.Sanbox: no such module/, &Options.config!/0
    Application.delete_env(:fluffy, Fluffy.Sanbox)

    put_env(file_input_max_bytes: 0)
    assert_raise ArgumentError, ~r/invalid config :fluffy: .*file_input_max_bytes/, &Options.config!/0
  end

  # Every driver uses Playwright's.
  test "rejects config :fluffy, test_id_attribute: for Playwright's" do
    put_env(test_id_attribute: "data-owl")

    assert_raise ArgumentError,
                 ~r/config :fluffy, test_id_attribute: is removed.*`config :playwright, :test, test_id_attribute: ...`/,
                 &Options.config!/0
  end

  # Only browsers wait for navigations, so the navigation timeout is Playwright's.
  test "rejects config :fluffy, navigation_timeout: for Playwright's" do
    put_env(navigation_timeout: 15_000)

    assert_raise ArgumentError,
                 ~r/config :fluffy, navigation_timeout: is removed.*`config :playwright, :test, navigation_timeout: ...`/,
                 &Options.config!/0
  end

  # Only what Playwright has no concept of is Fluffy's: the rest says what to set instead.
  test "rejects config :fluffy, action_timeout:, expect_timeout: and base_url: for Playwright's" do
    for {key, value, hint} <- [
          {:action_timeout, 4_000, ~r/`config :playwright, :test, action_timeout: \.\.\.`.*phoenix_backend_timeout/},
          {:expect_timeout, 500, ~r/`config :playwright, :expect, timeout: \.\.\.`.*phoenix_backend_timeout/},
          {:base_url, "http://localhost:4002", ~r/`config :playwright, :test, base_url: \.\.\.`/}
        ] do
      put_env([{key, value}])
      error = assert_raise ArgumentError, &Options.config!/0
      assert error.message =~ "config :fluffy, #{key}: is removed"
      assert error.message =~ hint
      Application.delete_env(:fluffy, key)
    end
  end

  # The test's action and navigation timeouts are resolved as it registers
  # (`Fluffy.Conformance.DefaultTimeoutTest`); these are read on every operation.
  test "a browser's expect timeout is Playwright's, a Phoenix session's phoenix_backend_timeout, 1 s by default" do
    assert {Timeouts.expect(), Timeouts.phoenix()} == {5_000, 1_000}

    put_playwright(expect: [timeout: 300])
    put_env(phoenix_backend_timeout: 2_000)
    assert {Timeouts.expect(), Timeouts.phoenix()} == {300, 2_000}

    put_env(phoenix_backend_timeout: 0)
    assert Timeouts.phoenix() == 0
  end

  # Playwright's `0` means no limit; Fluffy's checks once.
  test "Playwright's 0 is no limit" do
    put_playwright(expect: [timeout: 0])
    assert Timeouts.expect() == :infinity
  end

  test "rejects invalid values" do
    for {key, value} <- [phoenix_backend_timeout: -1] do
      put_env([{key, value}])
      assert_raise ArgumentError, ~r/invalid config :fluffy: .*#{key}/, &Options.config!/0
      Application.delete_env(:fluffy, key)
    end

    # Upstream's test id engine fails on a name that is not a CSS identifier.
    for name <- ["data-owl, data-hedwig", "data-owl]", "data:owl", "data-qa.id", "1owl", "data-owl,"] do
      put_playwright(test: [test_id_attribute: name])

      assert_raise ArgumentError,
                   ~r/invalid config :playwright, :test: test_id_attribute: .*attribute names/,
                   fn -> Options.config!(:test_id_attribute) end
    end

    put_playwright(test: [test_id_attribute: "data-owl,data_hedwig,data-élève,--owl"])
    assert Options.config!(:test_id_attribute) == "data-owl,data_hedwig,data-élève,--owl"
    Application.delete_env(:playwright, :test)
  end

  defp put_env(config), do: Enum.each(config, fn {key, value} -> Application.put_env(:fluffy, key, value) end)

  defp put_playwright(config), do: Enum.each(config, fn {key, value} -> Application.put_env(:playwright, key, value) end)
end
