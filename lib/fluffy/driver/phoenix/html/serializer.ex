defmodule Fluffy.Driver.Phoenix.HTML.Serializer do
  @moduledoc false

  # HTML's fragment serialization algorithm, which a browser's `outerHTML` follows, over a
  # LazyHTML tree: void elements have no end tag, and text and attribute values escape as
  # the browser does. LazyHTML's own serializer differs (`<br/>`, `&#39;`).

  # LazyHTML.Tree's tag lists, which follow the spec's.
  @void_tags ~w(area base basefont bgsound br col embed frame hr img input keygen link meta param source track wbr)
  @raw_text_tags ~w(style script xmp iframe noembed noframes plaintext)

  @spec to_html(LazyHTML.Tree.t()) :: String.t()
  def to_html(nodes), do: nodes |> serialize(:html, false) |> IO.iodata_to_binary()

  defp serialize(nodes, ns, raw?), do: Enum.map(nodes, &node(&1, ns, raw?))

  defp node({tag, attributes, children}, ns, _raw?) do
    ns = element_ns(tag, ns)
    start = ["<", tag, Enum.map(attributes, fn {name, value} -> [" ", name, "=\"", escape(value, true), "\""] end), ">"]

    if ns == :html and tag in @void_tags,
      do: start,
      else: [start, serialize(children, children_ns(tag, ns), ns == :html and tag in @raw_text_tags), "</", tag, ">"]
  end

  defp node({:comment, content}, _ns, _raw?), do: ["<!--", content, "-->"]
  defp node(text, _ns, true) when is_binary(text), do: text
  defp node(text, _ns, false) when is_binary(text), do: escape(text, false)

  # The tree has no namespaces, so these infer them from the tags, as LazyHTML.Tree does but
  # without its `annotation-xml encoding="text/html"` and `mglyph`/`malignmark` cases.
  defp element_ns("svg", ns) when ns in [:html, :math_text], do: :svg
  defp element_ns("math", ns) when ns in [:html, :math_text], do: :math
  defp element_ns(_tag, :math_text), do: :html
  defp element_ns(_tag, ns), do: ns

  defp children_ns(tag, :svg) when tag in ["foreignObject", "desc", "title"], do: :html
  defp children_ns(tag, :math) when tag in ["mi", "mo", "mn", "ms", "mtext"], do: :math_text
  defp children_ns(_tag, ns), do: ns

  # The spec's escapes: `&` and no-break spaces, `"` in attribute values, and `<` and `>`.
  defp escape(text, true), do: String.replace(text, ["&", "\u00A0", "\"", "<", ">"], &escape/1)
  defp escape(text, false), do: String.replace(text, ["&", "\u00A0", "<", ">"], &escape/1)

  defp escape("&"), do: "&amp;"
  defp escape("\u00A0"), do: "&nbsp;"
  defp escape("\""), do: "&quot;"
  defp escape("<"), do: "&lt;"
  defp escape(">"), do: "&gt;"
end
