defmodule Fluffy.Conformance.LiveActionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

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
      |> expect("Guardian head count: 1" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "routes a component-targeted event with #{driver}", %{driver: driver} do
      session = live_session(driver)

      session
      |> visit("/live/fluffy")
      |> click(by_role(:button, name: "Summon phoenix", exact: true))
      |> expect("Phoenix count: 1" |> by_text() |> to_be_visible())
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
      |> expect(child |> by_text("Child current: child@example.test", exact: true) |> to_be_visible())
      |> click(save_child)
      |> expect(child |> by_text("Child saved: child@example.test", exact: true) |> to_be_visible())
      |> expect("Parent saved: none" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "routes a click to the owning nested LiveView with #{driver}", %{driver: driver} do
      child = by_css("#nested-child")

      driver
      |> live_session()
      |> visit("/live/nested")
      |> click(by_role(child, :button, name: "Increment child", exact: true))
      |> expect(child |> by_text("Child count: 1", exact: true) |> to_be_visible())
      |> expect("Parent count: 0" |> by_text(exact: true) |> to_be_visible())
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
      |> expect(child |> by_text("Child count: 1", exact: true) |> to_be_visible())
      |> expect("Parent count: 0" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "follows navigation from the owning nested LiveView with #{driver}", %{driver: driver} do
      child = by_css("#nested-child")

      driver
      |> live_session()
      |> visit("/live/nested")
      |> click(by_role(child, :button, name: "Navigate from child", exact: true))
      |> expect("The secret chamber is open" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Fluffy.TestServer.base_url() <> "/live/secret-chamber"))
    end

    @tag driver: driver
    test "commits a patch from the owning nested LiveView with #{driver}", %{driver: driver} do
      child = by_css("#nested-child")

      driver
      |> live_session()
      |> visit("/live/nested")
      |> click(by_role(child, :button, name: "Patch from child", exact: true))
      |> expect(Fluffy.Expect.page_to_have_url(Fluffy.TestServer.base_url() <> "/live/nested?from=child"))
    end
  end

  test "Live ignores data-confirm before dispatching its event" do
    :phoenix
    |> live_session()
    |> visit("/live/mystic-creatures")
    |> click(by_role(:button, name: "Confirm", exact: true))
    |> expect("confirmed" |> by_text(exact: true) |> to_be_visible())
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "a button JS.dispatch change sends its name and value through the owning form with #{driver}" do
      unquote(driver)
      |> live_session()
      |> visit("/live/mystic-creatures")
      |> click(by_role(:button, name: "Reset via change", exact: true))
      |> expect("Dispatched action: reset" |> by_text(exact: true) |> to_be_visible())
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
      |> expect("Attribute payload state: checked" |> by_text(exact: true) |> to_be_visible())
      |> uncheck(attrs)
      |> expect("Attribute payload state: unchecked" |> by_text(exact: true) |> to_be_visible())
      |> check(js)
      |> expect("JS payload state: checked" |> by_text(exact: true) |> to_be_visible())
      |> uncheck(js)
      |> expect("JS payload state: unchecked" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "an outside-form radio sends its clicked value with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/mystic-creatures")
      |> check(by_label("Griffin", exact: true))
      |> expect("Selected creature: griffin" |> by_text(exact: true) |> to_be_visible())
    end
  end

  defp live_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
