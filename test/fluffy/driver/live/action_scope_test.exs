defmodule Fluffy.Driver.Live.ActionScopeTest do
  use ExUnit.Case, async: true

  alias Fluffy.Driver.Live.ActionScope

  test "a nested scope leaves the enclosing scope as it was" do
    ActionScope.run(fn ->
      ActionScope.record_delivery()
      ActionScope.run(fn -> refute ActionScope.delivered?() end)
      assert ActionScope.delivered?()
    end)

    refute ActionScope.delivered?()
  end
end
