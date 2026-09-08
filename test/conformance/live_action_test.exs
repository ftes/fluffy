defmodule Fluffy.Conformance.LiveActionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Page

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "resolves a composed locator before dispatching a Live event with #{driver}", %{
      driver: driver
    } do
      session = live_session(driver)

      parent_button =
        "section[data-zone='primary']"
        |> by_css()
        |> by_role(:button, name: "Rouse guardian head", exact: true)

      session
      |> visit("/live/fluffy")
      |> click(parent_button)
      |> expect(visible(by_text("Guardian head count: 1")))
    end

    @tag driver: driver
    test "routes a component-targeted event with #{driver}", %{driver: driver} do
      session = live_session(driver)

      session
      |> visit("/live/fluffy")
      |> click(by_role(:button, name: "Summon phoenix", exact: true))
      |> expect(visible(by_text("Phoenix count: 1")))
    end

    @tag driver: driver
    test "routes form changes and submission to the owning nested LiveView with #{driver}", %{
      driver: driver
    } do
      child = by_css("#nested-child")
      child_email = by_label(child, "Child email", exact: true)
      save_child = by_role(child, :button, name: "Save child", exact: true)

      session = live_session(driver)

      session
      |> visit("/live/nested")
      |> fill(child_email, "child@example.test")
      |> expect(visible(by_text(child, "Child current: child@example.test", exact: true)))
      |> click(save_child)
      |> expect(visible(by_text(child, "Child saved: child@example.test", exact: true)))
      |> expect(visible(by_text("Parent saved: none", exact: true)))
    end

    @tag driver: driver
    test "routes a click to the owning nested LiveView with #{driver}", %{driver: driver} do
      child = by_css("#nested-child")

      driver
      |> live_session()
      |> visit("/live/nested")
      |> click(by_role(child, :button, name: "Increment child", exact: true))
      |> expect(visible(by_text(child, "Child count: 1", exact: true)))
      |> expect(visible(by_text("Parent count: 0", exact: true)))
    end

    @tag driver: driver
    test "retries an action and then routes it to the owning nested LiveView with #{driver}", %{
      driver: driver
    } do
      child = by_css("#nested-child")

      driver
      |> live_session()
      |> visit("/live/nested")
      |> click(by_role(child, :button, name: "Schedule child action", exact: true))
      |> click(by_role(child, :button, name: "Delayed child action", exact: true))
      |> expect(visible(by_text(child, "Child count: 1", exact: true)))
      |> expect(visible(by_text("Parent count: 0", exact: true)))
    end

    @tag driver: driver
    test "follows navigation from the owning nested LiveView with #{driver}", %{driver: driver} do
      child = by_css("#nested-child")

      driver
      |> live_session()
      |> visit("/live/nested")
      |> click(by_role(child, :button, name: "Navigate from child", exact: true))
      |> expect(visible(by_text("The secret chamber is open")))
      |> expect(Page.to_have_url(Fluffy.TestServer.base_url() <> "/live/secret-chamber"))
    end

    @tag driver: driver
    test "commits a patch from the owning nested LiveView with #{driver}", %{driver: driver} do
      child = by_css("#nested-child")

      driver
      |> live_session()
      |> visit("/live/nested")
      |> click(by_role(child, :button, name: "Patch from child", exact: true))
      |> expect(Page.to_have_url(Fluffy.TestServer.base_url() <> "/live/nested?from=child"))
    end
  end

  test "Live ignores data-confirm before dispatching its event" do
    :phoenix
    |> live_session()
    |> visit("/live/mystic-creatures")
    |> click(by_role(:button, name: "Confirm", exact: true))
    |> expect(visible(by_text("confirmed", exact: true)))
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "a button JS.dispatch change sends its name and value through the owning form with #{driver}" do
      unquote(driver)
      |> live_session()
      |> visit("/live/mystic-creatures")
      |> click(by_role(:button, name: "Reset via change", exact: true))
      |> expect(visible(by_text("Dispatched action: reset", exact: true)))
    end

    @tag driver: driver
    test "outside-form checkboxes preserve phx-value and JS.push payloads with #{driver}", %{
      driver: driver
    } do
      attrs = by_label("Attribute payload", exact: true)
      js = by_label("JS payload", exact: true)

      driver
      |> live_session()
      |> visit("/live/mystic-creatures")
      |> check(attrs)
      |> expect(visible(by_text("Attribute payload state: checked", exact: true)))
      |> uncheck(attrs)
      |> expect(visible(by_text("Attribute payload state: unchecked", exact: true)))
      |> check(js)
      |> expect(visible(by_text("JS payload state: checked", exact: true)))
      |> uncheck(js)
      |> expect(visible(by_text("JS payload state: unchecked", exact: true)))
    end

    @tag driver: driver
    test "an outside-form radio sends its clicked value with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/mystic-creatures")
      |> check(by_label("Griffin", exact: true))
      |> expect(visible(by_text("Selected creature: griffin", exact: true)))
    end
  end

  defp live_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
