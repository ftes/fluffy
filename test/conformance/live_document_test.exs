defmodule Fluffy.Conformance.LiveDocumentTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "locates root layout content around a LiveView with #{driver}", %{driver: driver} do
      nav = by_role(:navigation, name: "Kennel")

      driver
      |> kennel_session()
      |> visit("/live/kennel")
      |> expect(to_be_visible(nav))
      |> expect(nav |> by_role(:link) |> to_have_count(3))
      |> expect("html[lang=en] > body > nav" |> by_css() |> to_have_count(1))
      |> expect(:heading |> by_role(name: "Fluffy's kennel") |> to_be_visible())
    end

    @tag driver: driver
    test "applies LiveView title updates through live_title with #{driver}", %{driver: driver} do
      driver
      |> kennel_session()
      |> visit("/live/kennel")
      |> expect(page_to_have_title("Kennel · Fluffy's kennel"))
      |> click(by_role(:button, name: "Rename kennel"))
      |> expect(page_to_have_title("Kennel · Fluffy & friends"))
    end

    @tag driver: driver
    test "dispatches root layout bindings to the main LiveView with #{driver}", %{driver: driver} do
      driver
      |> kennel_session()
      |> visit("/live/kennel")
      |> click(by_role(:button, name: "Bark"))
      |> expect("Barks: loud" |> by_text() |> to_be_visible())
      |> fill(by_label("Tune"), "Lullaby")
      |> click(by_role(:button, name: "Whistle"))
      |> expect("Tune: Lullaby" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "follows root layout links with #{driver}", %{driver: driver} do
      driver
      |> kennel_session()
      |> visit("/live/kennel")
      |> click(by_role(:link, name: "Garden"))
      |> expect(page_to_have_url("/live/kennel?yard=garden"))
      |> expect("Yard: garden" |> by_text() |> to_be_visible())
      |> click(by_role(:link, name: "Kitchen"))
      |> expect(page_to_have_url("/live/kennel/kitchen"))
      |> expect(:heading |> by_role(name: "Kennel kitchen") |> to_be_visible())
      |> click(by_role(:link, name: "Chamber"))
      |> expect(page_to_have_url("/chamber"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "renders and acts on portal content in its target with #{driver}", %{driver: driver} do
      dialog = by_role(:dialog, name: "Treats")

      driver
      |> kennel_session()
      |> visit("/live/kennel")
      |> expect(to_be_visible(dialog))
      |> expect("#portal-root > [data-phx-teleported-src=treat-portal] > #treat-dialog" |> by_css() |> to_have_count(1))
      |> click(by_role(dialog, :button, name: "Give treat"))
      |> expect(dialog |> by_text("Treats: 1") |> to_be_visible())
      |> fill(by_label(dialog, "Treat name"), "Bone")
      |> click(by_role(dialog, :button, name: "Name treat"))
      |> expect(dialog |> by_text("Treat name: Bone") |> to_be_visible())
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "teleports a portal nested in portal content with #{driver}", %{driver: driver} do
      status = by_role(:status, name: "Bones")

      driver
      |> kennel_session()
      |> visit("/live/kennel")
      |> expect(to_be_visible(status))
      |> expect("body > [data-phx-teleported-src=bone-portal] > #bone-status" |> by_css() |> to_have_count(1))
      |> click(by_role(status, :button, name: "Bury bone"))
      |> expect(status |> by_text("Bones: 1") |> to_be_visible())
    end
  end

  @tag driver: :playwright
  test "interacts with a LiveView rendered in the root layout with playwright" do
    :playwright
    |> kennel_session()
    |> visit("/live/kennel")
    |> click(by_role(:button, name: "Nap"))
    |> expect("Naps: 1" |> by_text() |> to_be_visible())
  end

  @tag driver: :phoenix
  test "reads but does not connect a LiveView rendered in the root layout with phoenix" do
    session =
      :phoenix
      |> kennel_session()
      |> visit("/live/kennel")
      |> expect("Naps: 0" |> by_text() |> to_be_visible())

    error = assert_raise Fluffy.CapabilityError, fn -> click(session, by_role(:button, name: "Nap")) end
    assert error.capability == :root_layout_live_views
  end

  defp kennel_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
