defmodule Fluffy.Driver.Live.Document do
  @moduledoc false

  # LiveViewTest renders only the LiveView container element. A browser keeps
  # the dead-rendered root layout around it, applies title updates to <title>,
  # and teleports portal content into its target. Rebuild that document from
  # the initial `live/2` HTML after every render.

  # The layout is serialized once around placeholders for the view and the
  # title text. Every render then builds one HTML string, applies portals to
  # it, and parses it once.

  @enforce_keys [:parts, :title]
  defstruct [:parts, :title]

  @type title :: %{text: String.t(), html: String.t(), prefix: String.t(), suffix: String.t(), default: String.t() | nil}
  @type t :: %__MODULE__{parts: [String.t() | :view | :title], title: title() | nil}

  @node_marker "data-fluffy-node"
  @view_marker "fluffy-live-view"
  @title_marker "fluffy-live-title"

  @spec new(String.t(), String.t()) :: t()
  def new(html, view_id) when is_binary(html) and is_binary(view_id) do
    tree = html |> LazyHTML.from_document() |> LazyHTML.to_tree()
    title = tree |> find_title() |> title_state()

    tree =
      tree
      |> replace_element(view_id, [{:comment, @view_marker}])
      |> update_first(&match?({"title", _attributes, _children}, &1), fn {"title", attributes, _children} ->
        {"title", attributes, [@title_marker]}
      end)

    layout = serialize(tree)
    %__MODULE__{parts: split(layout, ["<!--#{@view_marker}-->", @title_marker]), title: title}
  end

  @spec compose(t(), String.t(), String.t() | nil) :: LazyHTML.t()
  def compose(%__MODULE__{} = shell, view_html, page_title) when is_binary(view_html) do
    title_html = title_html(shell.title, page_title)

    shell.parts
    |> Enum.map(fn
      :view -> view_html
      :title -> title_html
      part -> part
    end)
    |> IO.iodata_to_binary()
    |> teleport_portals()
    |> LazyHTML.from_document()
  end

  # LazyHTML.from_tree/1 is far slower than serializing and parsing again.
  defp serialize(tree), do: "<!DOCTYPE html>" <> LazyHTML.Tree.to_html(tree)

  defp split(layout, [view_marker, title_marker]) do
    markers = Regex.compile!("(#{Regex.escape(view_marker)}|#{Regex.escape(title_marker)})")

    markers
    |> Regex.split(layout, include_captures: true)
    |> Enum.map(fn
      ^view_marker -> :view
      ^title_marker -> :title
      part -> part
    end)
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
  defp title_html(nil, _page_title), do: ""
  defp title_html(title, nil), do: title.html

  defp title_html(title, page_title) do
    text = unescape(page_title)

    cond do
      normalize(page_title) == title.text -> title.html
      String.trim(text) != "" -> escape(title.prefix <> text <> title.suffix)
      is_binary(title.default) -> escape(title.prefix <> title.default <> title.suffix)
      true -> title.html
    end
  end

  defp find_title(nodes) do
    Enum.find_value(nodes, fn
      {"title", _attributes, _children} = title -> title
      {tag, _attributes, children} when is_binary(tag) -> find_title(children)
      _text_or_comment -> nil
    end)
  end

  defp title_state(nil), do: nil

  defp title_state({"title", attributes, _children} = title) do
    text = [title] |> LazyHTML.from_tree() |> LazyHTML.text()

    %{
      text: normalize(text),
      html: escape(text),
      prefix: attribute(attributes, "data-prefix") || "",
      suffix: attribute(attributes, "data-suffix") || "",
      default: attribute(attributes, "data-default")
    }
  end

  # document.title strips and collapses ASCII whitespace.
  defp normalize(text), do: text |> String.split(~r/[\t\n\f\r ]+/, trim: true) |> Enum.join(" ")

  defp unescape(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.text()
  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  # Mirrors DOMPatch.teleport in the LiveView client: append the template's
  # root element to the target and mark it with the owning view and source.
  defp teleport_portals(html) do
    if String.contains?(html, "data-phx-portal"),
      do: html |> LazyHTML.from_document() |> LazyHTML.to_tree() |> teleport_tree(),
      else: html
  end

  # Teleport one portal at a time and rescan, so portals inside teleported
  # content are found too, like the client's teleports after each morph.
  defp teleport_tree(tree, teleported_ids \\ []) do
    case tree |> portals(nil, []) |> Enum.reverse() |> Enum.find(&(&1.id not in teleported_ids)) do
      nil -> serialize(tree)
      portal -> tree |> teleport(portal) |> teleport_tree([portal.id | teleported_ids])
    end
  end

  defp teleport(tree, portal) do
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
        portals(children, owning_view_id(attributes, view_id), acc)

      _text_or_comment, acc ->
        acc
    end)
  end

  # Teleported content belongs to the view that owns its portal.
  defp owning_view_id(attributes, view_id) do
    cond do
      teleported = attribute(attributes, "data-phx-teleported") -> teleported
      attribute(attributes, "data-phx-session") -> attribute(attributes, "id")
      true -> view_id
    end
  end

  # Resolve the portal's CSS target like document.querySelector by tagging
  # every element with its pre-order position and querying the tagged tree.
  defp target_index(tree, selector) do
    {tagged, _next} = tag_elements(tree, 0)

    case tagged |> serialize() |> LazyHTML.from_document() |> LazyHTML.query(selector) |> Enum.at(0) do
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
