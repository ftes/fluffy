defmodule Fluffy.CapabilityMatrixTest do
  use Fluffy.TestCase, async: true

  alias Fluffy.Capability

  @capability_document Path.expand("../docs/capabilities.md", __DIR__)
  @external_resource @capability_document

  test "declares every driver and only documented statuses" do
    assert Capability.matrix_version() == 1

    for capability <- Capability.matrix() do
      assert capability.drivers |> Map.keys() |> Enum.sort() == Enum.sort(Capability.drivers())

      assert Enum.all?(capability.drivers, fn {_driver, status} ->
               status in Capability.statuses()
             end)

      for driver <- Capability.drivers() do
        assert Capability.status(capability.id, driver) == capability.drivers[driver]
      end
    end
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
