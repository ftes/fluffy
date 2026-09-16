defmodule Fluffy.HTML.DocumentIndexTest do
  use ExUnit.Case, async: true

  alias Fluffy.HTML.DocumentIndex

  test "maps duplicate-looking siblings and multiple fragment roots to unique nodes" do
    document =
      LazyHTML.from_fragment("""
      <section><span>x</span><span>x</span></section>
      <section><span>x</span></section>
      """)

    index = DocumentIndex.new(document)

    targets =
      document
      |> LazyHTML.query("span")
      |> Enum.map(&DocumentIndex.target!(index, &1))

    assert Enum.map(targets, & &1.id) == [1, 2, 4]

    assert Enum.map(targets, & &1.selector) == [
             "section:nth-of-type(1) > span:nth-of-type(1)",
             "section:nth-of-type(1) > span:nth-of-type(2)",
             "section:nth-of-type(2) > span:nth-of-type(1)"
           ]
  end

  test "preserves nested SVG and LiveComponent-shaped ancestry" do
    document =
      LazyHTML.from_fragment("""
      <div id="component" data-phx-component="1">
        <svg><g><circle></circle><circle></circle></g></svg>
      </div>
      """)

    index = DocumentIndex.new(document)
    [circle] = document |> LazyHTML.query("circle:nth-child(2)") |> Enum.to_list()
    target = DocumentIndex.target!(index, circle)

    assert Enum.map(target.ancestors, & &1.tag) == ["div", "svg", "g"]
    assert target.selector =~ "circle:nth-of-type(2)"
  end

  test "maps every selector-visible template boundary without entering inert content" do
    document =
      LazyHTML.from_fragment("<template><span>inert</span></template><span>outside</span>")

    index = DocumentIndex.new(document)

    targets =
      document
      |> LazyHTML.query("*")
      |> Enum.map(&DocumentIndex.target!(index, &1))

    assert Enum.map(targets, & &1.tag) == ["template", "span"]
    assert Enum.map(targets, & &1.id) == [0, 2]
    assert Enum.map(DocumentIndex.all_targets(index), & &1.id) == [0, 2]
  end

  test "uses the first visible HTML id for explicit form ownership" do
    document =
      LazyHTML.from_fragment("""
      <template><form id="owner"><input name="inert"></form></template>
      <div id="owner"></div>
      <input form="owner" name="orphaned">
      <form id="owner"><input name="owned"></form>
      """)

    index = DocumentIndex.new(document)
    targets = Map.new(DocumentIndex.targets_by_tag(index, "input"), &{hd(&1.attributes), &1})
    [owner] = DocumentIndex.targets_by_tag(index, "form")

    refute Map.has_key?(index.form_owner_ids, targets[{"form", "owner"}].id)
    assert Map.fetch!(index.form_owner_ids, targets[{"name", "owned"}].id) == owner.id
  end

  test "a disabled fieldset exempts its first legend subtree" do
    document =
      LazyHTML.from_fragment("""
      <fieldset disabled>
        <legend><button id="legend-button">Legend action</button></legend>
        <button id="disabled-button">Disabled action</button>
      </fieldset>
      """)

    index = DocumentIndex.new(document)
    targets = Map.new(DocumentIndex.targets_by_tag(index, "button"), &{hd(&1.attributes), &1})

    refute targets[{"id", "legend-button"}].disabled?
    assert targets[{"id", "disabled-button"}].disabled?
  end
end
