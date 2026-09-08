defmodule Fluffy.Driver.Registry do
  @moduledoc false

  def module(:static), do: Fluffy.Driver.Static
  def module(:live), do: Fluffy.Driver.Live
  def module(:playwright), do: Fluffy.Driver.Playwright
end
