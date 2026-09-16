defmodule Fluffy.StrictnessError do
  @moduledoc """
  Raised internally when a single-target query resolves to zero or multiple elements.
  Public Phoenix actions preserve this exception in `Fluffy.OperationError.cause`.
  """

  defexception [:locator, :candidates, :message]

  @impl true
  def exception(options) do
    locator = Keyword.fetch!(options, :locator)
    candidates = Keyword.fetch!(options, :candidates)

    %__MODULE__{
      locator: locator,
      candidates: candidates,
      message: Fluffy.Expectation.strictness_message(locator, candidates)
    }
  end
end
