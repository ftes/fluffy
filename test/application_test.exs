defmodule Fluffy.ApplicationTest do
  use Fluffy.TestCase, async: true

  test "starts the Fluffy supervision tree" do
    assert Process.alive?(Process.whereis(Fluffy.Supervisor))
  end

  test "starts no Playwright transport or browser before the first browser session" do
    assert %{runtime: %{initialized?: false, launch_count: 0}, transport: nil} =
             Application.fetch_env!(:fluffy, :playwright_boot_state)
  end
end
