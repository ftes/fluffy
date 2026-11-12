defmodule Fluffy.PlaywrightConfigurationTest do
  # Changes Fluffy's global config.
  use ExUnit.Case, async: false

  alias Fluffy.Options
  alias Fluffy.Timeouts

  @keys [:timeout, :playwright, :action_timeout, :navigation_timeout, :expect_timeout, :test_id_attribute]

  setup do
    originals = for key <- @keys, do: {key, Application.fetch_env(:fluffy, key)}
    Enum.each(@keys, &Application.delete_env(:fluffy, &1))

    on_exit(fn ->
      for {key, original} <- originals do
        case original do
          {:ok, value} -> Application.put_env(:fluffy, key, value)
          :error -> Application.delete_env(:fluffy, key)
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
                 ~r/config :fluffy, playwright: is removed.*action_timeout.*navigation_timeout.*expect_timeout/,
                 &Options.config!/0

    put_env(playwright: false)
    assert Options.config!()
  end

  test "defaults to Playwright Test's timeouts and test id attribute" do
    assert {Timeouts.action(), Timeouts.navigation(), Timeouts.expect()} == {:infinity, :infinity, 5_000}
    assert Options.config!(:test_id_attribute) == "data-testid"

    put_env(action_timeout: 2_000, navigation_timeout: 3_000, expect_timeout: 1_000, test_id_attribute: "data-owl")
    assert {Timeouts.action(), Timeouts.navigation(), Timeouts.expect()} == {2_000, 3_000, 1_000}
    assert Options.config!(:test_id_attribute) == "data-owl"

    put_env(action_timeout: :infinity, navigation_timeout: :infinity, expect_timeout: :infinity)
    assert {Timeouts.action(), Timeouts.navigation(), Timeouts.expect()} == {:infinity, :infinity, :infinity}
  end

  # As a call's `timeout: 0`, `expect_timeout: 0` checks once; Playwright actions and
  # navigations can't, so their defaults reject it.
  test "a configured 0 checks assertions once and is rejected for actions and navigations" do
    put_env(expect_timeout: 0)
    assert Timeouts.expect() == 0

    for key <- [:action_timeout, :navigation_timeout] do
      put_env([{key, 0}])

      assert_raise ArgumentError, ~r/invalid config :fluffy: .*#{key}.*got: 0.*use :infinity/, fn ->
        Options.config!(key)
      end

      Application.delete_env(:fluffy, key)
    end
  end

  test "rejects invalid values" do
    for {key, value} <- [action_timeout: -1, navigation_timeout: "1s", expect_timeout: -1, test_id_attribute: ""] do
      put_env([{key, value}])
      assert_raise ArgumentError, ~r/invalid config :fluffy: .*#{key}/, &Options.config!/0
      Application.delete_env(:fluffy, key)
    end
  end

  defp put_env(config), do: Enum.each(config, fn {key, value} -> Application.put_env(:fluffy, key, value) end)
end
