defmodule Fluffy.CapabilityMatrixTest do
  use Fluffy.Support.Case, async: true

  alias Fluffy.Capability

  @capability_document Path.expand("../docs/capabilities.md", __DIR__)
  @external_resource @capability_document

  test "declares every Phoenix driver with a documented status" do
    for capability <- Capability.matrix() do
      assert capability.drivers |> Map.keys() |> Enum.sort() == [:live, :static]
      assert Enum.all?(Map.values(capability.drivers), &(&1 in Capability.statuses()))
    end
  end

  # A `Fluffy.CapabilityError`'s `capability` is a matrix id, which `Capability.status/2`
  # looks up.
  test "every raised capability is in the matrix" do
    raised =
      for file <- Path.wildcard(Path.expand("../lib/**/*.ex", __DIR__)),
          pattern <- [
            ~r/capability: :(\w+)/,
            ~r/require_playwright!\(\s*[^,]+,\s*:(\w+)/,
            ~r/(?:browser_context!\(|set_context!\(\s*session,)\s*:(\w+)/
          ],
          [_match, id] <- Regex.scan(pattern, File.read!(file)),
          uniq: true,
          do: String.to_atom(id)

    assert :pages in raised and :browser_context_setters in raised
    assert raised -- Capability.ids() == []
  end

  test "published table is rendered from the machine-readable matrix" do
    document = File.read!(@capability_document)

    assert [_, published] =
             Regex.run(
               ~r/<!-- capability-matrix:start -->\n(.*?)\n<!-- capability-matrix:end -->/s,
               document
             )

    assert published == Capability.markdown()
    refute published =~ "| Static |"
    refute published =~ "browser only"
    refute published =~ "live_connect_params"
  end
end
