defmodule Fluffy.TestCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import Fluffy.TestCase, only: [assert_action_error: 4]
    end
  end

  def assert_action_error(session, structural_exception, structural_message, action) do
    error = ExUnit.Assertions.assert_raise(Fluffy.OperationError, action)
    ExUnit.Assertions.assert(error.driver == Fluffy.Session.current_driver(session))
    ExUnit.Assertions.assert(is_atom(error.operation) and not is_nil(error.operation))
    ExUnit.Assertions.assert(match?(%Fluffy.Locator{}, error.locator))

    if Fluffy.Session.current_driver(session) == :playwright do
      ExUnit.Assertions.assert(error.backend == :playwright)
      ExUnit.Assertions.assert(match?(%{error: %{name: name}} when is_binary(name), error.cause))
    else
      ExUnit.Assertions.assert(error.backend == :phoenix)
      ExUnit.Assertions.assert(error.cause.__struct__ == structural_exception)
      ExUnit.Assertions.assert(Exception.message(error.cause) =~ structural_message)
    end

    error
  end

  setup context do
    :ok = Fluffy.Test.setup(context, sandbox: false)
  end
end
