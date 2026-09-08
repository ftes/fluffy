defmodule Fluffy.Backend.Registry do
  @moduledoc false

  def module(:phoenix), do: Fluffy.Backend.Phoenix
  def module(:playwright), do: Fluffy.Backend.Playwright
end
