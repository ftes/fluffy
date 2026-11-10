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
  end

  defp start_test_session(driver) do
    start_session(driver, base_url: Fluffy.TestServer.base_url(), endpoint: Fluffy.TestWeb.Endpoint)
  end
end
