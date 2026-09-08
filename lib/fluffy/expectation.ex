defmodule Fluffy.Expectation do
  @moduledoc false

  alias Fluffy.Locator

  def assert_count!(%Locator{} = locator, expected, candidates) do
    actual = length(candidates)

    if actual != expected do
      raise ExUnit.AssertionError,
        message: count_message(locator, expected, actual, candidates)
    end

    :ok
  end

  def raise_count!(%Locator{} = locator, expected, candidates) do
    raise ExUnit.AssertionError,
      message: count_message(locator, expected, length(candidates), candidates)
  end

  def count_message(locator, expected, actual, candidates) do
    String.trim("""
    Expected #{Locator.describe(locator)} to match #{expected} element(s), but it matched #{actual}.
    #{candidate_section(candidates)}
    """)
  end

  def strictness_message(locator, candidates) do
    String.trim("""
    Expected #{Locator.describe(locator)} to resolve to exactly one element, but it matched #{length(candidates)}.
    #{candidate_section(candidates)}
    """)
  end

  defp candidate_section([]), do: "Candidates: none"

  defp candidate_section(candidates) do
    snippets =
      candidates
      |> Enum.take(5)
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {candidate, index} -> "  #{index}. #{snippet(candidate)}" end)

    suffix = if length(candidates) > 5, do: "\n  …", else: ""
    "Candidates:\n" <> snippets <> suffix
  end

  defp snippet(candidate) do
    candidate
    |> LazyHTML.to_html(skip_whitespace_nodes: true)
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> truncate(180)
  end

  defp truncate(text, maximum) do
    if String.length(text) <= maximum do
      text
    else
      String.slice(text, 0, maximum - 3) <> "..."
    end
  end
end
