defmodule Fluffy.TestCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import Fluffy.TestCase, only: [assert_action_error: 4, playwright_engine?: 1]
    end
  end

  @playwright_engine Application.compile_env!(:fluffy, :playwright)[:engine]

  # A plain function, compiled before the tests, so `@tag skip:` can call it at compile time.
  def playwright_engine?(engine), do: engine == @playwright_engine

  def assert_action_error(session, structural_exception, structural_message, action) do
    error = ExUnit.Assertions.assert_raise(Fluffy.OperationError, action)
    ExUnit.Assertions.assert(error.driver == Fluffy.Session.current_driver(session))
    ExUnit.Assertions.assert(is_atom(error.operation) and not is_nil(error.operation))
    ExUnit.Assertions.assert(match?(%Fluffy.Locator{}, error.locator))

    if Fluffy.Session.current_driver(session) == :playwright do
      ExUnit.Assertions.assert(error.backend == :playwright)

      ExUnit.Assertions.assert(
        is_exception(error.cause) and error.cause.__struct__ |> Module.split() |> hd() == "PlaywrightEx"
      )
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
