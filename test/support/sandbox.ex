defmodule Fluffy.TestSandbox do
  @moduledoc false

  def allow(repo, owner, child) do
    send(owner, {:fluffy_test_sandbox_allow, repo, child})
    Ecto.Adapters.SQL.Sandbox.allow(repo, owner, child)
  end
end
