defmodule Fluffy.Driver.Registry do
  @moduledoc false

  def module(:static), do: Fluffy.Driver.Static
  def module(:live), do: Fluffy.Driver.Live
  def module(:playwright), do: Fluffy.Driver.Playwright
  def module(:external), do: Fluffy.Driver.External
end
