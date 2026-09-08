defmodule Fluffy.TestCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  setup context do
    :ok = Fluffy.Test.setup(context, sandbox: false)
  end
end
