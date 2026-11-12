defmodule Fluffy.Support.Sandbox do
  @moduledoc false

  # Refuses owner == child, as `Mox.allow/3` does.
  def allow(_repo, pid, pid), do: raise(ArgumentError, "owner_pid and allowed_pid must be different")

  def allow(repo, owner, child) do
    send(owner, {:fluffy_test_sandbox_allow, repo, child})
    Ecto.Adapters.SQL.Sandbox.allow(repo, owner, child)
  end
end
