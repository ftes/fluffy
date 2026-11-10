defmodule Fluffy.Conformance.LivePatchReconcileTest do
  use Fluffy.TestCase, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestHTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "checked state stays on its id-less radio when a patch inserts an element before it with #{driver}", %{
      driver: driver
    } do
      driver
      |> start_test_session()
      |> visit("/live/radio-shift")
      |> check(by_role(:radio, name: "c"))
      |> expect("Choice: c" |> by_text() |> to_be_visible())
      |> expect(to_be_checked(by_role(:radio, name: "c")))
      |> expect("input[type=radio]:checked" |> by_css() |> to_have_count(1))
    end

    @tag driver: driver
    test "a server-rendered radio choice clears a local choice in its group with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/radio-shift?override=a")
      |> click(by_role(:radio, name: "c"))
      |> expect("Choice: c" |> by_text() |> to_be_visible())
      |> expect(to_be_checked(by_role(:radio, name: "a")))
      |> expect("input[type=radio]:checked" |> by_css() |> to_have_count(1))
    end

    @tag driver: driver
    test "local checkbox state does not move to a shifted id-less sibling with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/radio-shift")
      |> click(by_role(:checkbox, name: "y"))
      |> expect("Changed: true" |> by_text() |> to_be_visible())
      |> expect(to_be_checked(by_role(:checkbox, name: "x"), checked: false))
    end

    @tag driver: driver
    test "a select's choice does not move to a shifted id-less select with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/shifted-controls")
      |> select_option(by_label("Second", exact: true), "y")
      |> expect("Changed: true" |> by_text() |> to_be_visible())
      |> expect(to_have_value(by_label("First", exact: true), "x"))
      |> expect(to_have_value(by_label("Second", exact: true), "x"))
    end

    @tag driver: driver
    test "a file selection does not move to a shifted id-less file input with #{driver}", %{driver: driver} do
      fixture = TestHTTPFixtures.register(%{body: "<!doctype html><html><body><h1>Saved</h1></body></html>"})
      action = TestHTTPFixtures.path(fixture, "/submit")

      driver
      |> start_test_session()
      |> visit("/live/shifted-controls?action=#{URI.encode_www_form(action)}")
      |> set_input_files(by_label("Second file"), Path.expand("../support/fixtures/fluffy-upload.txt", __DIR__))
      |> fill(by_label("Trigger"), "shift")
      |> expect("Changed: true" |> by_text() |> to_be_visible())
      |> click(by_role(:button, name: "Save"))
      |> expect("Saved" |> by_text() |> to_be_visible())

      [submission] = TestHTTPFixtures.requests(fixture)
      refute submission.body =~ ~s(filename="fluffy-upload.txt")
    end

    @tag driver: driver
    test "a title update keeps typed text with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/patched-controls")
      |> fill(by_label("Note", exact: true), "typed")
      |> click(by_role(:button, name: "Retitle"))
      |> expect(page_to_have_title("Retitled controls"))
      |> expect(to_have_value(by_label("Note", exact: true), "typed"))
    end

    @tag driver: driver
    test "a view patch resets typed text in the view but not in an unchanged component with #{driver}", %{
      driver: driver
    } do
      driver
      |> start_test_session()
      |> visit("/live/patched-controls")
      |> fill(by_label("Note", exact: true), "typed")
      |> fill(by_label("Component note"), "typed")
      |> click(by_role(:button, name: "Bump", exact: true))
      |> expect("Count: 1" |> by_text() |> to_be_visible())
      |> expect(to_have_value(by_label("Note", exact: true), ""))
      |> expect(to_have_value(by_label("Component note"), "typed"))
    end

    @tag driver: driver
    test "a component patch resets typed text in the component but not in its view with #{driver}", %{
      driver: driver
    } do
      driver
      |> start_test_session()
      |> visit("/live/patched-controls")
      |> fill(by_label("Note", exact: true), "typed")
      |> fill(by_label("Component note"), "typed")
      |> click(by_role(:button, name: "Bump component"))
      |> expect("Component count: 1" |> by_text() |> to_be_visible())
      |> expect(to_have_value(by_label("Note", exact: true), "typed"))
      |> expect(to_have_value(by_label("Component note"), ""))
    end

    @tag driver: driver
    test "a view patch keeps typed text in an unchanged component's portal with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/patched-controls")
      |> fill(by_label("Portal note"), "typed")
      |> click(by_role(:button, name: "Bump", exact: true))
      |> expect("Count: 1" |> by_text() |> to_be_visible())
      |> expect(to_have_value(by_label("Portal note"), "typed"))
    end

    @tag driver: driver
    test "a component patch resets typed text in its portal but not in its view with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/patched-controls")
      |> fill(by_label("Note", exact: true), "typed")
      |> fill(by_label("Portal note"), "typed")
      |> click(by_role(:button, name: "Bump component"))
      |> expect("Component count: 1" |> by_text() |> to_be_visible())
      |> expect(to_have_value(by_label("Note", exact: true), "typed"))
      |> expect(to_have_value(by_label("Portal note"), ""))
    end

    @tag driver: driver
    test "a view patch keeps typed text in the root layout but resets it in the view's portal with #{driver}", %{
      driver: driver
    } do
      dialog = by_role(:dialog, name: "Treats")

      driver
      |> start_test_session()
      |> visit("/live/kennel")
      |> fill(by_label("Tune"), "Lullaby")
      |> fill(by_label(dialog, "Treat name"), "Bone")
      |> click(by_role(dialog, :button, name: "Give treat"))
      |> expect(dialog |> by_text("Treats: 1") |> to_be_visible())
      |> expect(to_have_value(by_label("Tune"), "Lullaby"))
      |> expect(to_have_value(by_label(dialog, "Treat name"), ""))
    end

    for {label, pick, rendered} <- [{"Pick", "b", "a"}, {"Preset", "c", "b"}] do
      @tag driver: driver
      test "a view patch resets the #{label} select to its rendered option with #{driver}", %{driver: driver} do
        driver
        |> start_test_session()
        |> visit("/live/patched-controls")
        |> select_option(by_label(unquote(label)), unquote(pick))
        |> click(by_role(:button, name: "Bump", exact: true))
        |> expect("Count: 1" |> by_text() |> to_be_visible())
        |> expect(to_have_value(by_label(unquote(label)), unquote(rendered)))
      end
    end

    @tag driver: driver
    test "a view patch resets a multiple select to its rendered options with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/patched-controls")
      |> select_option(by_label("Many"), ["a"])
      |> click(by_role(:button, name: "Bump", exact: true))
      |> expect("Count: 1" |> by_text() |> to_be_visible())
      |> expect(to_have_values(by_label("Many"), ["b"]))
    end

    @tag driver: driver
    test "a view patch resets a checkbox and radio to their rendered state but not an ignored one with #{driver}", %{
      driver: driver
    } do
      driver
      |> start_test_session()
      |> visit("/live/patched-checks")
      |> check(by_label("Loose", exact: true))
      |> check(by_label("Loose b"))
      |> check(by_label("Ignored"))
      |> click(by_role(:button, name: "Bump"))
      |> expect("Count: 1" |> by_text() |> to_be_visible())
      |> expect(to_be_checked(by_label("Loose", exact: true), checked: false))
      |> expect(to_be_checked(by_label("Loose a")))
      |> expect(to_be_checked(by_label("Ignored")))
    end

    # Even with focus, LiveView resets a checkbox or radio to its rendered state.
    # These click: Playwright's check fails when the patch beats its own check
    # of the new state, as it does in Firefox.
    @tag driver: driver
    test "a checkbox's own phx-change patch resets it to its rendered state with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/patched-checks")
      |> click(by_label("Tracked"))
      |> expect("Changes: 1" |> by_text() |> to_be_visible())
      |> expect(to_be_checked(by_label("Tracked"), checked: false))
    end

    @tag driver: driver
    test "a checkbox's phx-click patch resets it though its phx-change renders nothing with #{driver}", %{
      driver: driver
    } do
      driver
      |> start_test_session()
      |> visit("/live/patched-checks")
      |> click(by_label("Clicked"))
      |> expect("Count: 1" |> by_text() |> to_be_visible())
      |> expect(to_be_checked(by_label("Clicked"), checked: false))
    end

    @tag driver: driver
    test "a radio's own phx-change patch resets its group to the rendered choice with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/patched-checks")
      |> click(by_label("Pick b"))
      |> expect("Changes: 1" |> by_text() |> to_be_visible())
      |> expect(to_be_checked(by_label("Pick a")))
    end

    @tag driver: driver
    test "a title update keeps a select's choice with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/patched-controls")
      |> select_option(by_label("Pick"), "b")
      |> click(by_role(:button, name: "Retitle"))
      |> expect(page_to_have_title("Retitled controls"))
      |> expect(to_have_value(by_label("Pick"), "b"))
    end
  end

  defp start_test_session(driver) do
    start_session(driver, base_url: Fluffy.TestServer.base_url(), endpoint: Fluffy.TestWeb.Endpoint)
  end
end
