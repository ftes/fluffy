defmodule Fluffy.HTML.DocumentIndexTest do
  use ExUnit.Case, async: true

  alias Fluffy.HTML.DocumentIndex

  for parser <- [:from_fragment, :from_document] do
    test "native paths match index entries in #{parser}" do
      document =
        apply(LazyHTML, unquote(parser), [
          """
          <main>
            text <!-- comments do not count as element siblings -->
            <span id="first">same</span>
            <template><span id="inert">same</span></template>
            <strong id="middle">same</strong>
            <span id="last">same</span>
          </main>
          <aside><span id="other-root">same</span></aside>
          """
        ])

      index = DocumentIndex.new(document)
      elements = document |> LazyHTML.query("*") |> Enum.to_list()

      assert length(elements) == length(index.entries)

      for {element, entry} <- Enum.zip(elements, index.entries) do
        assert DocumentIndex.fetch_by_element(index, element) == {:ok, entry}
        assert DocumentIndex.id!(index, element) == entry.id
        assert LazyHTML.tag(element) == [entry.tag]
        assert LazyHTML.attributes(element) == [entry.attributes]
        target = DocumentIndex.target_by_id(index, entry.id)
        assert DocumentIndex.path(target.element) == DocumentIndex.path(element)

        [css_path] = LazyHTML.css_path(element)
        [selected] = document |> LazyHTML.query(css_path) |> Enum.to_list()
        assert LazyHTML.to_tree(selected) == LazyHTML.to_tree(element)
      end
    end
  end

  test "tree-walk paths match native CSS paths for escaped tag names" do
    document = LazyHTML.from_fragment("<x:box><x.foo></x.foo></x:box><x:box></x:box>")
    index = DocumentIndex.new(document)
    elements = document |> LazyHTML.query("*") |> Enum.to_list()

    assert Enum.map(index.entries, & &1.path) == LazyHTML.css_path(LazyHTML.query(document, "*"))

    for {element, entry} <- Enum.zip(elements, index.entries) do
      assert DocumentIndex.fetch_by_element(index, element) == {:ok, entry}
    end
  end

  test "tree-walk paths match native CSS identifier edge cases" do
    tags = [
      "1st-item",
      "-1st-item",
      "-",
      "--item",
      "item\u001F",
      "item\u007F",
      "éclair",
      "item😀",
      "item\\name",
      "item name",
      "item\u{10FFFF}",
      "_item-12",
      "x:nth-child(2)",
      "x>y"
    ]

    document = LazyHTML.from_tree(Enum.map(tags, &{&1, [], [{"span", [], []}]}))
    index = DocumentIndex.new(document)
    elements = LazyHTML.query(document, "*")

    assert Enum.map(index.entries, & &1.path) == LazyHTML.css_path(elements)

    for {element, entry} <- Enum.zip(elements, index.entries) do
      assert DocumentIndex.fetch_by_element(index, element) == {:ok, entry}
    end
  end

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
