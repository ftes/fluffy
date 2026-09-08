defmodule Fluffy.StrictnessError do
  @moduledoc """
  Raised when a single-target operation resolves to zero or multiple elements.
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
