defmodule Fluffy.PlaywrightConfigurationTest do
  # Changes Fluffy's and PlaywrightEx's global config.
  use ExUnit.Case, async: false

  alias Fluffy.Options
  alias Fluffy.Timeouts

  @keys [:timeout, :playwright, :action_timeout, :navigation_timeout, :expect_timeout, :test_id_attribute]

  setup do
    originals = for key <- @keys, do: {key, Application.fetch_env(:fluffy, key)}
    Enum.each(@keys, &Application.delete_env(:fluffy, &1))
    playwright_ex = for key <- [:test, :expect], do: {key, Application.fetch_env(:playwright_ex, key)}
    Enum.each([:test, :expect], &Application.delete_env(:playwright_ex, &1))

    on_exit(fn ->
      for {key, original} <- originals do
        case original do
          {:ok, value} -> Application.put_env(:fluffy, key, value)
          :error -> Application.delete_env(:fluffy, key)
        end
      end

      for {key, original} <- playwright_ex do
        case original do
          {:ok, value} -> Application.put_env(:playwright_ex, key, value)
          :error -> Application.delete_env(:playwright_ex, key)
        end
      end
    end)
  end

  test "rejects Fluffy's removed timeout config with the keys to use instead" do
    put_env(timeout: 2_000)

    assert_raise ArgumentError,
                 ~r/config :fluffy, timeout: is removed.*expect_timeout.*action_timeout/,
                 &Options.config!/0

    Application.delete_env(:fluffy, :timeout)

    put_env(playwright: [timeout: 15_000])

    assert_raise ArgumentError,
                 ~r/config :fluffy, playwright: is removed.*action_timeout.*expect_timeout.*:playwright_ex, :test, navigation_timeout/,
                 &Options.config!/0

    put_env(playwright: false)
    assert Options.config!()
  end

  # Only browsers wait for navigations, so the navigation timeout is PlaywrightEx's.
  test "rejects config :fluffy, navigation_timeout: for PlaywrightEx's" do
    put_env(navigation_timeout: 15_000)

    assert_raise ArgumentError,
                 ~r/config :fluffy, navigation_timeout: is removed.*`config :playwright_ex, :test, navigation_timeout: ...`/,
                 &Options.config!/0
  end

  test "unset, Fluffy's settings are PlaywrightEx's, with its defaults" do
    assert {Timeouts.action(), Timeouts.navigation(), Timeouts.expect()} == {:infinity, :infinity, 5_000}
    assert Options.config!(:test_id_attribute) == "data-testid"

    put_playwright_ex(
      test: [action_timeout: 2_000, navigation_timeout: 3_000, test_id_attribute: "data-owl"],
      expect: [timeout: 1_000]
    )

    assert {Timeouts.action(), Timeouts.navigation(), Timeouts.expect()} == {2_000, 3_000, 1_000}
    assert Options.config!(:test_id_attribute) == "data-owl"
  end

  test "Fluffy's settings win over PlaywrightEx's" do
    put_playwright_ex(
      test: [action_timeout: 2_000, navigation_timeout: 3_000, test_id_attribute: "data-owl"],
      expect: [timeout: 1_000]
    )

    put_env(action_timeout: 4_000, expect_timeout: 500, test_id_attribute: "data-hedwig")
    assert {Timeouts.action(), Timeouts.navigation(), Timeouts.expect()} == {4_000, 3_000, 500}
    assert Options.config!(:test_id_attribute) == "data-hedwig"

    put_env(action_timeout: :infinity, expect_timeout: :infinity)
    assert {Timeouts.action(), Timeouts.expect()} == {:infinity, :infinity}
  end

  # PlaywrightEx's `0` means no limit, as Playwright's; Fluffy's keep Fluffy's meaning.
  test "PlaywrightEx's 0 is no limit" do
    put_playwright_ex(test: [action_timeout: 0, navigation_timeout: 0], expect: [timeout: 0])
    assert {Timeouts.action(), Timeouts.navigation(), Timeouts.expect()} == {:infinity, :infinity, :infinity}
  end

  # As a call's `timeout: 0`, `expect_timeout: 0` checks once; Playwright actions can't, so
  # their default rejects it.
  test "Fluffy's 0 checks assertions once and is rejected for actions" do
    put_env(expect_timeout: 0)
    assert Timeouts.expect() == 0

    put_env(action_timeout: 0)

    assert_raise ArgumentError, ~r/invalid config :fluffy: .*action_timeout.*got: 0.*use :infinity/, fn ->
      Options.config!(:action_timeout)
    end
  end

  test "rejects invalid values" do
    for {key, value} <- [action_timeout: -1, expect_timeout: -1, test_id_attribute: ""] do
      put_env([{key, value}])
      assert_raise ArgumentError, ~r/invalid config :fluffy: .*#{key}/, &Options.config!/0
      Application.delete_env(:fluffy, key)
    end

    put_playwright_ex(test: [navigation_timeout: -1])
    assert_raise ArgumentError, ~r/invalid navigation_timeout/, &Timeouts.navigation/0
  end

  defp put_env(config), do: Enum.each(config, fn {key, value} -> Application.put_env(:fluffy, key, value) end)

  defp put_playwright_ex(config),
    do: Enum.each(config, fn {key, value} -> Application.put_env(:playwright_ex, key, value) end)
end
