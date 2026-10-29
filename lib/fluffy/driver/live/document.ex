defmodule Fluffy.Driver.Live.Document do
  @moduledoc false

  # LiveViewTest renders only the LiveView container element. A browser keeps
  # the dead-rendered root layout around it, applies title updates to <title>,
  # and teleports portal content into its target. Rebuild that document from
  # the initial `live/2` HTML after every render.

  @enforce_keys [:tree, :view_id, :title]
  defstruct [:tree, :view_id, :title]

  @type t :: %__MODULE__{tree: LazyHTML.Tree.t(), view_id: String.t(), title: String.t() | nil}

  @node_marker "data-fluffy-node"

  @spec new(String.t(), String.t()) :: t()
  def new(html, view_id) when is_binary(html) and is_binary(view_id) do
    tree = html |> LazyHTML.from_document() |> LazyHTML.to_tree()
    %__MODULE__{tree: tree, view_id: view_id, title: tree |> find_title() |> title_text()}
  end

  @spec compose(t(), String.t(), String.t() | nil) :: LazyHTML.t()
  def compose(%__MODULE__{} = shell, view_html, page_title) when is_binary(view_html) do
    view = view_html |> LazyHTML.from_fragment() |> LazyHTML.to_tree()

    shell.tree
    |> replace_element(shell.view_id, view)
    |> put_title(shell.title, page_title)
    |> teleport_portals()
    |> LazyHTML.from_tree()
  end

  defp replace_element(nodes, view_id, replacement) do
    Enum.flat_map(nodes, fn
      {tag, attributes, children} when is_binary(tag) ->
        if attribute(attributes, "id") == view_id do
          replacement
        else
          [{tag, attributes, replace_element(children, view_id, replacement)}]
        end

      node ->
        [node]
    end)
  end

  # Mirrors DOM.putTitle in the LiveView client. Before the first title update,
  # LiveViewTest reports the dead-rendered <title> text, which already includes
  # any prefix and suffix. Later updates arrive HTML-escaped and unwrapped.
  defp put_title(tree, _initial_title, nil), do: tree

  defp put_title(tree, initial_title, page_title) do
    if normalize(page_title) == initial_title, do: tree, else: update_title(tree, unescape(page_title))
  end

  defp update_title(tree, title) do
    update_first(tree, &match?({"title", _attributes, _children}, &1), fn {"title", attributes, children} ->
      prefix = attribute(attributes, "data-prefix") || ""
      suffix = attribute(attributes, "data-suffix") || ""
      default = attribute(attributes, "data-default")

      cond do
        String.trim(title) != "" -> {"title", attributes, [prefix <> title <> suffix]}
        is_binary(default) -> {"title", attributes, [prefix <> default <> suffix]}
        true -> {"title", attributes, children}
      end
    end)
  end

  defp find_title(nodes) do
    Enum.find_value(nodes, fn
      {"title", _attributes, _children} = title -> title
      {tag, _attributes, children} when is_binary(tag) -> find_title(children)
      _text_or_comment -> nil
    end)
  end

  defp title_text(nil), do: nil
  defp title_text(title), do: [title] |> LazyHTML.from_tree() |> LazyHTML.text() |> normalize()

  # document.title strips and collapses ASCII whitespace.
  defp normalize(text), do: text |> String.split(~r/[\t\n\f\r ]+/, trim: true) |> Enum.join(" ")

  defp unescape(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.text()

  # Mirrors DOMPatch.teleport in the LiveView client: append the template's
  # root element to the target and mark it with the owning view and source.
  defp teleport_portals(tree) do
    tree
    |> portals(nil, [])
    |> Enum.reverse()
    |> Enum.reduce(tree, fn portal, tree ->
      case target_index(tree, portal.target) do
        nil ->
          tree

        index ->
          teleported =
            put_attributes(portal.root, [
              {"data-phx-teleported", portal.view_id},
              {"data-phx-teleported-src", portal.id}
            ])

          update_at(tree, index, fn {tag, attributes, children} -> {tag, attributes, children ++ [teleported]} end)
      end
    end)
  end

  defp portals(nodes, view_id, acc) do
    Enum.reduce(nodes, acc, fn
      {"template", attributes, children}, acc ->
        with target when is_binary(target) <- attribute(attributes, "data-phx-portal"),
             id when is_binary(id) <- attribute(attributes, "id"),
             true <- is_binary(view_id),
             {_tag, _attributes, _children} = root <- Enum.find(children, &element?/1) do
          [%{id: id, root: root, target: target, view_id: view_id} | acc]
        else
          _not_a_portal -> acc
        end

      {tag, attributes, children}, acc when is_binary(tag) ->
        view_id = if attribute(attributes, "data-phx-session"), do: attribute(attributes, "id"), else: view_id
        portals(children, view_id, acc)

      _text_or_comment, acc ->
        acc
    end)
  end

  # Resolve the portal's CSS target like document.querySelector by tagging
  # every element with its pre-order position and querying the tagged tree.
  defp target_index(tree, selector) do
    {tagged, _next} = tag_elements(tree, 0)

    case tagged |> LazyHTML.from_tree() |> LazyHTML.query(selector) |> Enum.at(0) do
      nil -> nil
      element -> element |> LazyHTML.attribute(@node_marker) |> List.first() |> String.to_integer()
    end
  rescue
    ArgumentError -> nil
  end

  defp tag_elements(nodes, index) do
    Enum.map_reduce(nodes, index, fn
      {tag, attributes, children}, index when is_binary(tag) ->
        {children, next} = tag_elements(children, index + 1)
        {{tag, [{@node_marker, Integer.to_string(index)} | attributes], children}, next}

      node, index ->
        {node, index}
    end)
  end

  defp update_at(tree, target, fun) do
    {tree, _next} = update_at(tree, target, fun, 0)
    tree
  end

  defp update_at(nodes, target, fun, index) do
    Enum.map_reduce(nodes, index, fn
      {tag, attributes, children}, index when is_binary(tag) ->
        {updated_children, next} = update_at(children, target, fun, index + 1)
        element = {tag, attributes, updated_children}
        {if(index == target, do: fun.(element), else: element), next}

      node, index ->
        {node, index}
    end)
  end

  defp update_first(nodes, match?, fun) do
    {nodes, _found?} = update_first(nodes, match?, fun, false)
    nodes
  end

  defp update_first(nodes, match?, fun, found?) do
    Enum.map_reduce(nodes, found?, fn
      node, true ->
        {node, true}

      {tag, attributes, children} = element, false when is_binary(tag) ->
        if match?.(element) do
          {fun.(element), true}
        else
          {children, found?} = update_first(children, match?, fun, false)
          {{tag, attributes, children}, found?}
        end

      node, false ->
        {node, false}
    end)
  end

  defp put_attributes({tag, attributes, children}, additions) do
    names = Enum.map(additions, &elem(&1, 0))
    {tag, Enum.reject(attributes, fn {name, _value} -> name in names end) ++ additions, children}
  end

  defp element?({tag, _attributes, _children}) when is_binary(tag), do: true
  defp element?(_node), do: false

  defp attribute(attributes, name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end
end
