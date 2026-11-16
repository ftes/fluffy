defmodule Fluffy.ApplicationTest do
  use Fluffy.Support.Case, async: true

  test "starts the Fluffy supervision tree" do
    assert Process.alive?(Process.whereis(Fluffy.Supervisor))
  end

  test "starts no Playwright driver or browser before the first browser session" do
    assert %{pool: nil} = :persistent_term.get({Fluffy.ApplicationTest, :boot_state})
  end
end
