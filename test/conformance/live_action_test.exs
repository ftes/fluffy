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
    test "routes a check's change to the nested LiveView its click moved with #{driver}", %{driver: driver} do
      child = by_css("#nested-child")

      driver
      |> live_session()
      |> visit("/live/nested")
      |> check_reverted(by_label(child, "Shift child", exact: true))
      |> expect("Child shifted" |> by_text(exact: true) |> to_be_visible())
      |> expect(child |> by_text("Child shift changes: 1", exact: true) |> to_be_visible())
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
      |> click(attrs)
      |> expect("Attribute payload state: checked" |> by_text(exact: true) |> to_be_visible())
      |> click(attrs)
      |> expect("Attribute payload state: unchecked" |> by_text(exact: true) |> to_be_visible())
      |> check(js)
      |> expect("JS payload state: checked" |> by_text(exact: true) |> to_be_visible())
      |> uncheck(js)
      |> expect("JS payload state: unchecked" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "checkable click payloads omit unchecked values and preserve explicit overrides with #{driver}", %{
      driver: driver
    } do
      component = by_label("Component payload", exact: true)
      overridden = by_label("Override payload", exact: true)
      metadata = %{"id" => "component", "key" => "kept"}
      checked_payload = metadata |> Map.put("value", "on") |> inspect()
      unchecked_payload = inspect(metadata)
      override_payload = metadata |> Map.put("value", "from-js") |> inspect()

      driver
      |> live_session()
      |> visit("/live/mystic-creatures")
      |> check(component)
      |> expect(checked_payload |> by_text(exact: true) |> to_be_visible())
      |> uncheck(component)
      |> expect(unchecked_payload |> by_text(exact: true) |> to_be_visible())
      |> check(overridden)
      |> expect(override_payload |> by_text(exact: true) |> to_be_visible())
      |> uncheck(overridden)
      |> expect(override_payload |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "an outside-form radio sends its clicked value with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/mystic-creatures")
      |> check(by_label("Griffin", exact: true))
      |> expect("Selected creature: griffin" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "clicking a checkbox or radio sends its phx-click, then its form's phx-change, with #{driver}", %{
      driver: driver
    } do
      agree = by_label("Agree", exact: true)
      medium = by_label("Size m", exact: true)
      notify = by_label("Notify", exact: true)
      log = by_css("#log")

      driver
      |> live_session()
      |> visit("/live/click-checkable")
      |> click(agree)
      |> expect(to_have_text(log, "Log: click:yes change:yes/-"))
      |> expect(to_be_checked(agree))
      |> click(agree)
      |> expect(to_have_text(log, "Log: click:yes change:yes/- click:- change:no/-"))
      |> expect(not_(to_be_checked(agree)))
      |> click(medium)
      |> expect(to_have_text(log, ~r/ click:m change:no\/m$/))
      |> expect(to_be_checked(medium))
      # A click on a selected radio changes nothing, so only the click is sent.
      |> click(medium)
      |> expect(to_have_text(log, ~r/ change:no\/m click:m$/))
      |> click(notify)
      |> expect(to_have_text(log, ~r/ click:m click:yes notify-change:yes$/))
      |> expect(to_be_checked(notify))
    end

    @tag driver: driver
    test "a click reaches the closest phx-click, and an inner binding wins, with #{driver}", %{driver: driver} do
      log = by_css("#log")

      driver
      |> live_session()
      |> visit("/live/click-bindings")
      |> click(by_text("Alpha", exact: true))
      |> expect(to_have_text(log, "Log: select:alpha"))
      |> click(by_role(:button, name: "Remove beta", exact: true))
      |> expect(to_have_text(log, "Log: select:alpha remove:beta"))
      |> click(by_text("Gamma", exact: true))
      |> expect(to_have_text(log, "Log: select:alpha remove:beta component-pick:gamma"))
      # The submit button has no binding of its own: the click reaches the
      # outer phx-click, then the button submits its form.
      |> click(by_role(:button, name: "Save", exact: true))
      |> expect(to_have_text(log, "Log: select:alpha remove:beta component-pick:gamma outer save"))
    end

    @tag driver: driver
    test "a click on text inside a submit button or link takes its default action with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/click-bindings")
      |> click(by_text("Save by text", exact: true))
      |> expect(to_have_text(by_css("#log"), "Log: save"))
      |> click(by_text("Leave by text", exact: true))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    # LiveView's link handler takes the click from the closest link before any
    # phx-click binding sees it.
    @tag driver: driver
    test "a click on text inside a LiveView link patches or navigates, past a closer phx-click, with #{driver}", %{
      driver: driver
    } do
      log = by_css("#log")

      driver
      |> live_session()
      |> visit("/live/click-bindings")
      |> click(by_text("Patch by text", exact: true))
      |> expect(to_have_text(by_css("#tab"), "Tab: two"))
      |> click(by_text("Alpha", exact: true))
      |> expect(to_have_text(log, "Log: select:alpha"))
      |> click(by_text("Navigate by text", exact: true))
      |> expect("The secret chamber is open" |> by_text() |> to_be_visible())
    end

    # Only a LiveView link or href="#" has its default action prevented.
    @tag driver: driver
    test "an element's own phx-click goes before its default action unless its href is # with #{driver}", %{
      driver: driver
    } do
      log = by_css("#log")
      page = Fluffy.TestServer.base_url() <> "/live/click-bindings"

      driver
      |> live_session()
      |> visit("/live/click-bindings")
      |> click(by_role(:link, name: "Track here", exact: true))
      |> expect(to_have_text(log, "Log: track"))
      |> expect(page_to_have_url(page))
      |> click(by_role(:button, name: "Track and save", exact: true))
      |> expect(to_have_text(log, "Log: track track save"))
      |> click(by_role(:link, name: "Track and leave", exact: true))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "unchecked checkboxes and deselected options leave the form payload with #{driver}", %{driver: driver} do
      last = by_css("#last")

      driver
      |> live_session()
      |> visit("/live/unchecked-controls")
      |> uncheck(by_label("Tag a", exact: true))
      |> expect(to_have_text(last, "Last: change tag_ids=b bare=on solo=on colours=red,green plan=pro"))
      |> click(by_label("Tag b", exact: true))
      |> expect(to_have_text(last, "Last: change tag_ids=- bare=on solo=on colours=red,green plan=pro"))
      |> uncheck(by_label("Bare", exact: true))
      |> expect(to_have_text(last, "Last: change tag_ids=- bare=- solo=on colours=red,green plan=pro"))
      |> uncheck(by_label("Solo", exact: true))
      |> expect(to_have_text(last, "Last: solo tag_ids=- bare=- solo=- colours=- plan=-"))
      |> select_option(by_label("Colours", exact: true), [])
      |> expect(to_have_text(last, "Last: change tag_ids=- bare=- solo=- colours=- plan=pro"))
      |> click(by_role(:button, name: "Save", exact: true))
      |> expect(to_have_text(last, "Last: save tag_ids=- bare=- solo=- colours=- plan=pro"))
    end

    @tag driver: driver
    test "a single select with every option deselected leaves the form payload with #{driver}", %{driver: driver} do
      last = by_css("#last")

      driver
      |> live_session()
      |> visit("/live/unchecked-controls")
      |> select_option(by_label("Plan", exact: true), [])
      |> expect(to_have_text(last, "Last: change tag_ids=a,b bare=on solo=on colours=red,green plan=-"))
    end

    @tag driver: driver
    test "the form's phx-value-* wins over a field of the same name with #{driver}", %{driver: driver} do
      last = by_css("#last")

      driver
      |> live_session()
      |> visit("/live/unchecked-controls")
      |> fill(by_label("Note", exact: true), "typed")
      |> expect(to_have_text(last, "Last: note-change note=meta"))
      |> click(by_role(:button, name: "Save note", exact: true))
      |> expect(to_have_text(last, "Last: note-save note=meta"))
    end
  end

  defp live_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
