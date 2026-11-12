defmodule Fluffy.PlaywrightConfigurationTest do
  use ExUnit.Case, async: true

  alias Fluffy.Options

  # Browser, driver and launch options are PlaywrightEx.Test's (`config :playwright_ex, :test`).
  test "validates Fluffy's Playwright configuration" do
    assert Enum.sort(Options.validate_playwright!(timeout: 2_000, isolate: true)) ==
             [isolate: true, timeout: 2_000]

    assert false == Options.validate_playwright!(false)

    for removed <- [
          log_browser_console: true,
          engine: :firefox,
          pool_size: 2,
          launch_options: [],
          executable: "playwright",
          enabled: true
        ] do
      assert_raise NimbleOptions.ValidationError, ~r/unknown options/, fn -> Options.validate_playwright!([removed]) end
    end
  end
end
