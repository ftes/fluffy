defmodule Fluffy.FrameLocator do
  @moduledoc """
  A lazy query identifying a frame to search inside with the Playwright driver.

  Create one with `Fluffy.Locator.frame_locator/1`, `Fluffy.Locator.frame_locator/2`, or
  `Fluffy.Locator.content_frame/1`. Pass it to the `Fluffy.Locator.by_*`
  builders to obtain ordinary element locators inside that frame.

  Frame scopes do not switch the active page. Actions and element assertions
  accept the resulting element locators, not this scope itself.
  """

  @enforce_keys [:owner]
  defstruct [:owner]

  @type t :: %__MODULE__{owner: Fluffy.Locator.t()}

  @doc "Returns the locator for the iframe element in its containing document."
  @spec owner(t()) :: Fluffy.Locator.t()
  def owner(%__MODULE__{owner: owner}), do: owner
end

defimpl Inspect, for: Fluffy.FrameLocator do
  import Inspect.Algebra

  def inspect(frame, _options) do
    concat(["#Fluffy.FrameLocator<", Fluffy.Locator.describe(frame.owner), " |> content_frame()>"])
  end
end
