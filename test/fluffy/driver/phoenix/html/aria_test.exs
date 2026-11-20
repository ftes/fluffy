defmodule Fluffy.Driver.Phoenix.HTML.AriaTest do
  use ExUnit.Case, async: true

  alias Fluffy.Driver.Phoenix.HTML.Aria

  test "a header cell at the document root is a column header" do
    document = LazyHTML.from_tree([{"th", [], ["H"]}])
    aria = Aria.new(document)

    assert [{node, _element}] = Aria.scoped_nodes(aria, document)
    assert Aria.role(aria, node) == "columnheader"
  end
end
