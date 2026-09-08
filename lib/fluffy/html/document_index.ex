defmodule Fluffy.HTML.DocumentIndex do
  @moduledoc false

  alias Fluffy.HTML.Semantics
  alias Fluffy.HTML.Target

  @enforce_keys [
    :document,
    :entries,
    :nodes_by_id,
    :nodes_by_path,
    :nodes_by_tag,
    :form_owner_ids,
    :disabled_ids
  ]
  defstruct [
    :document,
    :entries,
    :nodes_by_id,
    :nodes_by_path,
    :nodes_by_tag,
    :form_owner_ids,
    :disabled_ids
  ]

  @type path :: [{String.t(), pos_integer()}]

  @type entry :: %{
          attributes: [{String.t(), String.t()}],
          children: list(),
          id: non_neg_integer(),
          identity: term(),
          implicit_form_id: non_neg_integer() | nil,
          inert?: boolean(),
          parent_id: non_neg_integer() | nil,
          path: path(),
          selector_path: path(),
          tag: String.t()
        }

  @type t :: %__MODULE__{
          document: LazyHTML.t(),
          entries: [entry()],
          nodes_by_id: %{non_neg_integer() => entry()},
          nodes_by_path: %{path() => entry()},
          nodes_by_tag: %{String.t() => [entry()]},
          form_owner_ids: %{non_neg_integer() => non_neg_integer()},
          disabled_ids: MapSet.t(non_neg_integer())
        }

  @spec new(LazyHTML.t()) :: t()
  def new(%LazyHTML{} = document) do
    {all_entries, _next_id} = document |> LazyHTML.to_tree() |> index_nodes(nil, nil, false, [], [], 0)
    all_entries = Enum.reverse(all_entries)
    entries = Enum.reject(all_entries, & &1.inert?)
    nodes_by_id = Map.new(all_entries, &{&1.id, &1})
    nodes_by_path = Map.new(all_entries, &{&1.path, &1})
    elements_by_html_id = elements_by_html_id(entries)

    %__MODULE__{
      document: document,
      entries: entries,
      nodes_by_id: nodes_by_id,
      nodes_by_path: nodes_by_path,
      nodes_by_tag: Enum.group_by(entries, & &1.tag),
      form_owner_ids: form_owner_ids(entries, elements_by_html_id),
      disabled_ids: disabled_ids(entries)
    }
  end

  @spec path(LazyHTML.t()) :: path()
  def path(%LazyHTML{} = element), do: path(element, [])

  @spec fetch_by_element(t(), LazyHTML.t()) :: {:ok, entry()} | :error
  def fetch_by_element(%__MODULE__{} = index, %LazyHTML{} = element) do
    Map.fetch(index.nodes_by_path, path(element))
  end

  @spec fetch_by_id(t(), non_neg_integer()) :: {:ok, entry()} | :error
  def fetch_by_id(%__MODULE__{} = index, id), do: Map.fetch(index.nodes_by_id, id)

  @spec all_targets(t()) :: [Target.t()]
  def all_targets(%__MODULE__{} = index) do
    Enum.map(index.entries, &light_target(index, &1))
  end

  @spec targets_by_tag(t(), String.t() | [String.t()]) :: [Target.t()]
  def targets_by_tag(%__MODULE__{} = index, tags) do
    tags = List.wrap(tags)

    tags
    |> Enum.flat_map(&Map.get(index.nodes_by_tag, &1, []))
    |> Enum.sort_by(& &1.id)
    |> Enum.map(&light_target(index, &1))
  end

  @spec targets_with_attribute(t(), String.t(), String.t()) :: [Target.t()]
  def targets_with_attribute(%__MODULE__{} = index, tag, attribute) do
    index.nodes_by_tag
    |> Map.get(tag, [])
    |> Enum.filter(&(&1.tag == tag and Semantics.has_attribute?(&1.attributes, attribute)))
    |> Enum.map(&light_target(index, &1))
  end

  @spec descendants_by_tag(t(), non_neg_integer(), String.t() | [String.t()]) :: [Target.t()]
  def descendants_by_tag(%__MODULE__{} = index, parent_id, tags) do
    parent_path = Map.fetch!(index.nodes_by_id, parent_id).path
    tags = List.wrap(tags)

    tags
    |> Enum.flat_map(&Map.get(index.nodes_by_tag, &1, []))
    |> Enum.sort_by(& &1.id)
    |> Enum.filter(&(&1.tag in tags and descendant?(&1.path, parent_path)))
    |> Enum.map(&light_target(index, &1))
  end

  @spec id!(t(), LazyHTML.t() | Target.t()) :: non_neg_integer()
  def id!(%__MODULE__{}, %Target{id: id}), do: id
  def id!(%__MODULE__{} = index, %LazyHTML{} = element), do: Map.fetch!(index.nodes_by_path, path(element)).id

  @spec selector_for_id!(t(), non_neg_integer()) :: String.t()
  def selector_for_id!(%__MODULE__{} = index, id) do
    index.nodes_by_id |> Map.fetch!(id) |> Map.fetch!(:selector_path) |> selector()
  end

  @spec identity_present?(t(), term()) :: boolean()
  def identity_present?(%__MODULE__{entries: entries}, identity) do
    Enum.any?(entries, &(&1.identity == identity))
  end

  @spec form_owner(t(), Target.t()) :: Target.t() | nil
  def form_owner(%__MODULE__{} = index, %Target{id: id}) do
    case Map.fetch(index.form_owner_ids, id) do
      {:ok, owner_id} -> light_target(index, Map.fetch!(index.nodes_by_id, owner_id))
      :error -> nil
    end
  end

  @spec target_by_id(t(), non_neg_integer()) :: Target.t() | nil
  def target_by_id(%__MODULE__{} = index, id) do
    case Map.fetch(index.nodes_by_id, id) do
      {:ok, entry} ->
        element = index.document |> LazyHTML.query(selector(entry.selector_path)) |> Enum.at(0)
        if element, do: target_from_entry(index, entry, element)

      :error ->
        nil
    end
  end

  @spec ancestor_has_attribute?(t(), non_neg_integer(), String.t(), String.t()) :: boolean()
  def ancestor_has_attribute?(%__MODULE__{} = index, id, tag, attribute) do
    index.nodes_by_id
    |> Map.fetch!(id)
    |> has_ancestor_attribute?(index, tag, attribute)
  end

  @spec target!(t(), LazyHTML.t()) :: Target.t()
  def target!(%__MODULE__{} = index, %LazyHTML{} = element) do
    entry = Map.fetch!(index.nodes_by_path, path(element))
    target_from_entry(index, entry, element)
  end

  defp path(element, path) do
    [tag] = LazyHTML.tag(element)
    [position] = LazyHTML.nth_child(element)
    parent = LazyHTML.parent_node(element)
    path = [{tag, position} | path]

    case LazyHTML.tag(parent) do
      [] -> path
      [_parent_tag] -> path(parent, path)
    end
  end

  defp index_nodes(nodes, parent_id, implicit_form_id, inert?, parent_path, parent_selector_path, next_id) do
    {entries, next_id, _tag_counts, _element_position} =
      Enum.reduce(nodes, {[], next_id, %{}, 0}, fn
        {tag, attributes, children}, {entries, id, tag_counts, element_position}
        when is_binary(tag) ->
          tag_position = Map.get(tag_counts, tag, 0) + 1
          element_position = element_position + 1
          path = parent_path ++ [{tag, element_position}]
          selector_path = parent_selector_path ++ [{tag, tag_position}]

          entry = %{
            attributes: attributes,
            children: children,
            id: id,
            identity: identity(tag, attributes, selector_path),
            implicit_form_id: implicit_form_id,
            inert?: inert?,
            parent_id: parent_id,
            path: path,
            selector_path: selector_path,
            tag: tag
          }

          child_form_id = if tag == "form", do: id, else: implicit_form_id
          child_inert? = inert? or tag == "template"

          {descendants, following_id} =
            index_nodes(children, id, child_form_id, child_inert?, path, selector_path, id + 1)

          {
            descendants ++ [entry | entries],
            following_id,
            Map.put(tag_counts, tag, tag_position),
            element_position
          }

        _text_or_comment, accumulator ->
          accumulator
      end)

    {entries, next_id}
  end

  defp identity(tag, attributes, selector_path) do
    cond do
      html_id = Semantics.attribute(attributes, "id") -> {:html_id, tag, html_id}
      phx_id = Semantics.attribute(attributes, "data-phx-id") -> {:phx_id, tag, phx_id}
      true -> {:path, selector_path}
    end
  end

  defp selector(path) do
    Enum.map_join(path, " > ", fn {tag, position} -> "#{tag}:nth-of-type(#{position})" end)
  end

  defp target_from_entry(index, entry, element) do
    %Target{
      ancestors: ancestor_targets(index, entry),
      attributes: entry.attributes,
      children: entry.children,
      disabled?: MapSet.member?(index.disabled_ids, entry.id),
      element: element,
      id: entry.id,
      selector: selector(entry.selector_path),
      tag: entry.tag
    }
  end

  defp light_target(index, entry) do
    %Target{
      attributes: entry.attributes,
      children: entry.children,
      disabled?: MapSet.member?(index.disabled_ids, entry.id),
      id: entry.id,
      tag: entry.tag
    }
  end

  defp ancestor_targets(index, entry) do
    entry
    |> ancestor_entries(index, [])
    |> Enum.map(fn ancestor ->
      %Target{attributes: ancestor.attributes, id: ancestor.id, tag: ancestor.tag}
    end)
  end

  defp ancestor_entries(%{parent_id: nil}, _index, ancestors), do: ancestors

  defp ancestor_entries(%{parent_id: parent_id}, index, ancestors) do
    parent = Map.fetch!(index.nodes_by_id, parent_id)
    ancestor_entries(parent, index, [parent | ancestors])
  end

  defp has_ancestor_attribute?(%{parent_id: nil}, _index, _tag, _attribute), do: false

  defp has_ancestor_attribute?(%{parent_id: parent_id}, index, tag, attribute) do
    parent = Map.fetch!(index.nodes_by_id, parent_id)

    (parent.tag == tag and Semantics.has_attribute?(parent.attributes, attribute)) or
      has_ancestor_attribute?(parent, index, tag, attribute)
  end

  defp elements_by_html_id(entries) do
    Enum.reduce(entries, %{}, fn entry, by_html_id ->
      case Semantics.attribute(entry.attributes, "id") do
        nil -> by_html_id
        html_id -> Map.put_new(by_html_id, html_id, entry)
      end
    end)
  end

  defp form_owner_ids(entries, elements_by_html_id) do
    entries
    |> Enum.flat_map(fn entry ->
      owner_id =
        case Semantics.attribute(entry.attributes, "form") do
          nil ->
            entry.implicit_form_id

          html_id ->
            case Map.get(elements_by_html_id, html_id) do
              %{tag: "form", id: id} -> id
              _missing_or_non_form -> nil
            end
        end

      if owner_id, do: [{entry.id, owner_id}], else: []
    end)
    |> Map.new()
  end

  defp disabled_ids(entries) do
    entries
    |> Enum.filter(&(&1.tag == "fieldset" and Semantics.has_attribute?(&1.attributes, "disabled")))
    |> Enum.reduce(MapSet.new(), fn fieldset, disabled ->
      first_legend =
        Enum.find(entries, &(&1.parent_id == fieldset.id and &1.tag == "legend"))

      Enum.reduce(entries, disabled, fn entry, disabled ->
        cond do
          not descendant?(entry.path, fieldset.path) -> disabled
          first_legend && within?(entry.path, first_legend.path) -> disabled
          true -> MapSet.put(disabled, entry.id)
        end
      end)
    end)
  end

  defp descendant?(path, ancestor_path) do
    path != ancestor_path and Enum.take(path, length(ancestor_path)) == ancestor_path
  end

  defp within?(path, ancestor_path), do: path == ancestor_path or descendant?(path, ancestor_path)
end
