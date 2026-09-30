defmodule Fluffy.TestFormValue do
  @moduledoc false
  defstruct [:value]
end

defimpl String.Chars, for: Fluffy.TestFormValue do
  def to_string(%{value: value}), do: "custom:#{value}"
end
