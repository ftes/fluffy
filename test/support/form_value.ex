defmodule Fluffy.Support.FormValue do
  @moduledoc false
  defstruct [:value]
end

defimpl String.Chars, for: Fluffy.Support.FormValue do
  def to_string(%{value: value}), do: "custom:#{value}"
end
