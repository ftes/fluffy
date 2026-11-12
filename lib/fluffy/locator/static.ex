defmodule Fluffy.Locator.Static do
  @moduledoc false

  alias Fluffy.HTML.Aria
  alias Fluffy.HTML.Semantics
  alias Fluffy.Locator
  # StringUtils is internal to PlaywrightEx, which is pinned.
  alias PlaywrightEx.Isomorphic.LocatorUtils
  alias PlaywrightEx.Isomorphic.StringUtils
  alias PlaywrightEx.RegExp

  # Operations that search inside each candidate. As in Playwright's chains, they
  # find descendants only, except that its text engine also matches the scope itself.
  @descendant_queries [:css, :attribute, :test_id]

  def resolve(document, %Locator{} = locator), do: resolve(Aria.for_document(document), document, locator)

  # For a document built for one query, which must not evict the real document's model.
  def resolve_uncached(document, %Locator{} = locator), do: resolve(Aria.new(document), document, locator)

  # `root` is what the locator starts from; `aria` models the whole page, which
  # role, name and label computation looks across regardless of it.
  defp resolve(aria, root, %Locator{} = locator) do
    Enum.reduce(locator.operations, [root], fn
      {:and, right}, candidates ->
        matches = aria |> resolve(root, right) |> MapSet.new(&LazyHTML.css_path/1)
        Enum.filter(candidates, &MapSet.member?(matches, LazyHTML.css_path(&1)))

      {:or, right}, candidates ->
        matches = MapSet.new(candidates ++ resolve(aria, root, right), &LazyHTML.css_path/1)
        root |> LazyHTML.query("*") |> Enum.filter(&MapSet.member?(matches, LazyHTML.css_path(&1)))

      {:role, role, options}, candidates ->
        role_matches(candidates, aria, role, options)

      {:label, text, options}, candidates ->
        label_matches(candidates, aria, text, options)

      {:text, text, options}, candidates ->
        text_matches(candidates, aria, text, Keyword.get(options, :exact, false))

      {:filter, options}, candidates ->
        filter_candidates(candidates, aria, options)

      # `child` resolves separately inside each match of `parent`, `nth` included.
      {:within, parent, child}, candidates ->
        candidates
        |> Enum.flat_map(&resolve(aria, &1, parent))
        |> Enum.flat_map(&resolve(aria, &1, child))
        |> Enum.uniq_by(&LazyHTML.css_path/1)

      operation, candidates when elem(operation, 0) in @descendant_queries ->
        candidates
        |> Enum.flat_map(&(operation |> apply_operation([&1]) |> without_scope(&1, aria.index.document)))
        |> Enum.uniq_by(&LazyHTML.css_path/1)

      operation, candidates ->
        apply_operation(operation, candidates)
    end)
  end

  # Only the document, at the top of a query, can match itself.
  defp without_scope(matches, document, document), do: matches

  defp without_scope(matches, scope, _document) do
    path = LazyHTML.css_path(scope)
    Enum.reject(matches, &(LazyHTML.css_path(&1) == path))
  end

  def structurally_visible?(%Aria{} = aria, element), do: Aria.rendered?(aria, Aria.node_for(aria, element))

  defp apply_operation({:css, selector}, scopes) do
    query_scopes(scopes, selector)
  end

  defp apply_operation({:attribute, attribute_name, text, options}, scopes) do
    exact? = Keyword.get(options, :exact, false)

    scopes
    |> query_scopes("[#{attribute_name}]")
    |> Enum.filter(fn element ->
      element
      |> element_attribute(attribute_name)
      |> attribute_matches?(text, exact?)
    end)
  end

  # Playwright's test id engine: any of the comma-separated names of `test_id_attribute`,
  # Fluffy's config, which the Playwright driver's locators get too.
  defp apply_operation({:test_id, test_id}, scopes) do
    names = test_id_attribute_names()

    scopes
    |> query_scopes(Enum.map_join(names, ",", &"[#{&1}]"))
    |> Enum.filter(fn element -> Enum.any?(names, &(element_attribute(element, &1) == test_id)) end)
  end

  defp apply_operation({:nth, index}, scopes) do
    case Enum.at(scopes, index) do
      nil -> []
      element -> [element]
    end
  end

  defp filter_candidates(candidates, aria, options) do
    Enum.filter(candidates, fn candidate ->
      Enum.all?(options, fn
        {:has_text, text} -> contains_text?(text(aria, candidate), text)
        {:has_not_text, text} -> not contains_text?(text(aria, candidate), text)
        {:visible, visible?} -> structurally_visible?(aria, candidate) == visible?
        {:has, %Locator{} = child} -> resolve(aria, candidate, child) != []
        {:has_not, %Locator{} = child} -> resolve(aria, candidate, child) == []
      end)
    end)
  end

  defp role_matches(scopes, aria, role, options) do
    role = role |> to_string() |> String.downcase()
    expected_name = Keyword.get(options, :name)
    exact? = Keyword.get(options, :exact, false)

    scopes
    |> scoped_nodes(aria)
    |> Enum.filter(fn {node, _element} ->
      Aria.role(aria, node) == role and not Aria.hidden?(aria, node) and
        accessible_name_matches?(aria, node, expected_name, exact?)
    end)
    |> Enum.map(fn {_node, element} -> element end)
  end

  # Playwright's text engine also matches the scope itself, and keeps the deepest
  # matches: those without a matching descendant. Ids are preorder, so a match's
  # descendants are the matches up to its last_id.
  defp text_matches(scopes, aria, text, exact?) do
    scopes
    |> Enum.flat_map(&self_and_scoped_nodes(aria, &1))
    |> Enum.uniq_by(fn {node, _element} -> node.id end)
    |> Enum.sort_by(fn {node, _element} -> node.id end)
    |> Enum.filter(fn {node, _element} -> node_text_matches?(node, text, exact?) end)
    |> Enum.chunk_every(2, 1)
    |> Enum.flat_map(fn
      [{%{last_id: last_id}, _element}, {%{id: next_id}, _next}] when next_id <= last_id -> []
      [{_node, element} | _next] -> [element]
    end)
  end

  defp self_and_scoped_nodes(%Aria{index: %{document: document}} = aria, document), do: Aria.scoped_nodes(aria, document)
  defp self_and_scoped_nodes(aria, scope), do: [{Aria.node_for(aria, scope), scope} | Aria.scoped_nodes(aria, scope)]

  # Playwright's label engine: the elements in scope with a matching label, by
  # getElementLabels. A label or reference may be anywhere in the document.
  defp label_matches(scopes, aria, text, options) do
    exact? = Keyword.get(options, :exact, false)

    scopes
    |> scoped_nodes(aria)
    |> Enum.filter(fn {node, _element} ->
      aria |> Aria.element_labels(node) |> Enum.any?(&text_matches?(&1, text, exact?))
    end)
    |> Enum.map(fn {_node, element} -> element end)
  end

  defp scoped_nodes(scopes, aria) do
    scopes
    |> Enum.flat_map(&Aria.scoped_nodes(aria, &1))
    |> Enum.uniq_by(fn {node, _element} -> node.id end)
    |> Enum.sort_by(fn {node, _element} -> node.id end)
  end

  defp accessible_name_matches?(_aria, _node, nil, _exact?), do: true

  # As upstream, a regular expression sees the normalized accessible name.
  defp accessible_name_matches?(aria, node, %RegExp{} = expected, _exact?),
    do: expected |> RegExp.compile!() |> Regex.match?(aria |> Aria.name(node) |> StringUtils.normalize_white_space())

  defp accessible_name_matches?(aria, node, expected, exact?) do
    aria |> Aria.name(node) |> text_matches?(expected, exact?)
  end

  defp query_scopes(scopes, selector) do
    scopes
    |> Enum.flat_map(fn scope -> scope |> LazyHTML.query(selector) |> Enum.to_list() end)
    |> Enum.uniq()
  end

  defp node_text_matches?(%{tag: tag}, _expected, _exact?) when tag in ~w(script style noscript), do: false
  defp node_text_matches?(node, expected, exact?), do: text_matches?(Semantics.text(node), expected, exact?)

  defp text(aria, element), do: Semantics.text(Aria.node_for(aria, element))

  defp test_id_attribute_names,
    do: :test_id_attribute |> Fluffy.Options.config!() |> LocatorUtils.split_test_id_attribute_names()

  defp element_attribute(element, name) do
    case LazyHTML.attribute(element, name) do
      [value] -> value
      [] -> nil
    end
  end

  # `filter/2`'s `has_text:` is a case-insensitive substring or a regex, as in Playwright.
  defp contains_text?(actual, expected), do: text_matches?(actual, expected, false)

  defp text_matches?(nil, _expected, _exact?), do: false

  # As upstream, a regular expression ignores `exact?` and sees the text as is.
  defp text_matches?(actual, %RegExp{} = expected, _exact?), do: expected |> RegExp.compile!() |> Regex.match?(actual)

  defp text_matches?(actual, expected, true),
    do: StringUtils.normalize_white_space(actual) == StringUtils.normalize_white_space(expected)

  defp text_matches?(actual, expected, false) do
    actual
    |> StringUtils.normalize_white_space()
    |> String.downcase()
    |> String.contains?(expected |> StringUtils.normalize_white_space() |> String.downcase())
  end

  defp attribute_matches?(nil, _expected, _exact?), do: false
  defp attribute_matches?(actual, expected, true), do: actual == expected

  defp attribute_matches?(actual, expected, false) do
    String.contains?(String.downcase(actual), String.downcase(expected))
  end
end
