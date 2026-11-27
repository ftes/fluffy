defmodule Fluffy.Driver.Phoenix.ClientDOM.Diagnostics do
  @moduledoc false

  alias Fluffy.Driver.Phoenix.ClientDOM
  alias Fluffy.Driver.Phoenix.HTML.Aria
  alias Fluffy.Driver.Phoenix.HTML.Semantics
  alias Fluffy.StrictnessError
  alias Playwright.Isomorphic.StringUtils

  def missing_assertion(client_dom, locator) do
    case role_query(locator) do
      :no_role ->
        text = client_dom.document |> Semantics.document_text() |> StringUtils.normalize_white_space()
        "No element matched.\nPage text: #{inspect(text, printable_limit: 500)}"

      query ->
        "No element matched." <> other_names(client_dom, query)
    end
  end

  def missing_action(client_dom, %StrictnessError{candidates: []} = error) do
    %{error | message: error.message <> other_names(client_dom, role_query(error.locator))}
  end

  # Drop only the final role's name, retaining its query roots and other filters.
  defp role_query(locator) do
    case List.pop_at(locator.operations, -1) do
      {{:role, role, options}, scope} ->
        other = %{locator | operations: scope ++ [{:role, role, Keyword.delete(options, :name)}]}
        {:role, role, options, other}

      {{:within, parent, child}, scope} ->
        with {:role, role, options, other} <- role_query(child) do
          {:role, role, options, %{locator | operations: scope ++ [{:within, parent, other}]}}
        end

      _ ->
        :no_role
    end
  end

  defp other_names(_client_dom, :no_role), do: ""

  defp other_names(client_dom, {:role, role, options, other}) do
    if Keyword.has_key?(options, :name) do
      aria = Aria.for_document(client_dom.document)

      names =
        client_dom
        |> ClientDOM.resolve(other)
        |> Enum.take(5)
        |> Enum.map_join(", ", fn element ->
          node = Aria.node_for(aria, element)
          inspect(Aria.name(aria, node, options[:include_hidden] || false), printable_limit: 180)
        end)

      if names == "", do: "", else: " Other #{role} names in scope: #{names}"
    else
      ""
    end
  end
end
