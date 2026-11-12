defmodule Fluffy.PlaywrightConfigurationTest do
  # Changes the global config of Fluffy and PlaywrightEx.
  use ExUnit.Case, async: false

  alias Fluffy.Options
  alias Fluffy.Timeouts

  setup do
    originals =
      for {app, key} <- [fluffy: :timeout, fluffy: :playwright, playwright_ex: :test, playwright_ex: :expect],
          do: {app, key, Application.fetch_env(app, key)}

    on_exit(fn ->
      for {app, key, original} <- originals do
        case original do
          {:ok, value} -> Application.put_env(app, key, value)
          :error -> Application.delete_env(app, key)
        end
      end
    end)
  end

  # Fluffy's timeout config is gone: PlaywrightEx's, as Playwright Test's, sets the defaults.
  test "rejects Fluffy's removed timeout config" do
    for {key, value} <- [timeout: 2_000, playwright: [timeout: 15_000]] do
      put_env(:fluffy, key, value)

      assert_raise ArgumentError, ~r/config :fluffy, #{key}: is removed.*action_timeout/, fn ->
        Options.reject_removed_config!()
      end

      Application.delete_env(:fluffy, key)
    end

    put_env(:fluffy, :playwright, false)
    assert Options.reject_removed_config!() == :ok
  end

  test "reads the default timeouts from PlaywrightEx's config, as Playwright Test does" do
    put_env(:playwright_ex, :test, [])
    put_env(:playwright_ex, :expect, [])
    assert {Timeouts.action(), Timeouts.navigation(), Timeouts.expect()} == {:infinity, :infinity, 5_000}

    put_env(:playwright_ex, :test, action_timeout: 2_000, navigation_timeout: 3_000)
    put_env(:playwright_ex, :expect, timeout: 1_000)
    assert {Timeouts.action(), Timeouts.navigation(), Timeouts.expect()} == {2_000, 3_000, 1_000}

    # A configured 0 is no timeout, as in PlaywrightEx; an operation's own 0 checks once.
    put_env(:playwright_ex, :test, action_timeout: 0, navigation_timeout: :infinity)
    put_env(:playwright_ex, :expect, timeout: 0)
    assert {Timeouts.action(), Timeouts.navigation(), Timeouts.expect()} == {:infinity, :infinity, :infinity}
    assert Timeouts.get([timeout: 0], &Timeouts.expect/0) == 0

    put_env(:playwright_ex, :test, action_timeout: -1)
    assert_raise ArgumentError, ~r/config :playwright_ex, :test, action_timeout:/, &Timeouts.action/0
  end

  defp put_env(app, key, value), do: Application.put_env(app, key, value)
end
