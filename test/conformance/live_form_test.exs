defmodule Fluffy.Conformance.LiveFormTest do
  use Fluffy.TestCase, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "unchanged sticky LiveView renders preserve entered form values with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions?sticky=true")
      |> fill(by_label("Uncontrolled email"), "ada@example.test")
      |> fill(by_label("Uncontrolled name"), "Ada")
      |> expect("Uncontrolled email" |> by_label() |> to_have_value("ada@example.test"))
      |> expect("Uncontrolled name" |> by_label() |> to_have_value("Ada"))
    end

    @tag driver: driver
    test "Live changes use current properties and latest server DOM with #{driver}", %{
      driver: driver
    } do
      session = start_test_session(driver)

      first = by_label("First ingredient")
      last = by_label("Final ingredient")
      stubborn = by_label("Cauldron controlled")

      session
      |> visit("/live/potions")
      |> fill(first, "moonstone")
      |> expect(to_have_value(first, "moonstone"))
      |> expect("#hidden-version" |> by_css() |> to_have_value("version-2"))
      |> expect("Last target: profile/first" |> by_text() |> to_be_visible())
      |> expect("Unused first: false" |> by_text() |> to_be_visible())
      |> expect("Unused last: true" |> by_text() |> to_be_visible())
      |> fill(last, "phoenix feather")
      |> expect(to_have_value(last, "phoenix feather"))
      |> expect("#hidden-version" |> by_css() |> to_have_value("version-3"))
      |> expect("Last target: profile/last" |> by_text() |> to_be_visible())
      |> expect("Unused first: false" |> by_text() |> to_be_visible())
      |> expect("Unused last: false" |> by_text() |> to_be_visible())
      |> fill(stubborn, "silver dust")
      |> expect(to_have_value(stubborn, "silver dust"))
      |> fill(last, "dragon scale")
      |> expect(to_have_value(stubborn, "server-5"))
      |> expect("Last first: moonstone" |> by_text() |> to_be_visible())
      |> expect("Last last: dragon scale" |> by_text() |> to_be_visible())
      |> expect("Last version: version-4" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "Live submission serializes the final dynamic DOM with #{driver}", %{driver: driver} do
      session = start_test_session(driver)

      session =
        session
        |> visit("/live/potions")
        |> fill(by_label("Row 0"), "aconite")
        |> fill(by_label("Row 1"), "bezoar")
        |> fill(by_label("Row 2"), "cinder")
        |> click(by_role(:button, name: "Remove row 1"))
        |> expect("Row 1" |> by_label() |> to_have_count(0))
        |> click(by_role(:button, name: "Bottle potion", exact: true))

      session
      |> expect("Saved rows: aconite, cinder" |> by_text() |> to_be_visible())
      |> expect("Saved drop is only empty: true" |> by_text() |> to_be_visible())
      |> expect("Saved external: outside" |> by_text() |> to_be_visible())
      |> expect("Saved commit: save" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "Live check and select state round-trips through patches with #{driver}", %{
      driver: driver
    } do
      session = start_test_session(driver)

      enabled = by_role(:checkbox, name: "Enabled")
      colours = by_label("Potion colours")

      session
      |> visit("/live/potions")
      |> check(enabled)
      |> expect(to_be_checked(enabled))
      |> select_option(colours, ["blue", "green"])
      |> expect(to_have_values(colours, ["green", "blue"]))
      |> uncheck(enabled)
      |> expect(not_(to_be_checked(enabled)))
    end

    @tag driver: driver
    test "Live check dispatches phx-click only when checkedness changes with #{driver}", %{
      driver: driver
    } do
      session = start_test_session(driver)
      checkbox = by_role(:checkbox, name: "Enabled")

      session
      |> visit("/live/potions")
      |> check(checkbox)
      |> expect("Checkbox clicks: 1" |> by_text() |> to_be_visible())
      |> expect("Event targets: profile/enabled" |> by_text() |> to_be_visible())
      |> check(checkbox)
      |> expect("Checkbox clicks: 1" |> by_text() |> to_be_visible())
      |> uncheck(checkbox)
      |> expect("Checkbox clicks: 2" |> by_text() |> to_be_visible())
      |> expect("Event targets: profile/enabled, profile/enabled" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "Live submission uses controls added and renamed after editing with #{driver}", %{
      driver: driver
    } do
      session = start_test_session(driver)

      session
      |> visit("/live/potions")
      |> fill(by_label("First ingredient"), "moonstone")
      |> click(by_role(:button, name: "Change recipe and add ingredient"))
      |> expect("First ingredient" |> by_label() |> to_have_value("moonstone"))
      |> click(by_role(:button, name: "Bottle potion", exact: true))
      |> expect("Saved dynamic controls: true" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "Live keyed reorder and replacement reset the unfocused input with #{driver}", %{driver: driver} do
      draft = by_label("Potion draft A")

      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> fill(draft, "client draft")
      |> click(by_role(:button, name: "Reorder potion drafts"))
      |> expect("#drafts > div:first-child input" |> by_css() |> to_have_value("B"))
      |> expect(to_have_value(draft, "A"))
      |> fill(draft, "client draft")
      |> click(by_role(:button, name: "Replace potion draft A"))
      |> expect(to_have_value(draft, "A"))
    end

    @tag driver: driver
    test "Live keyed reorder preserves the focused input with #{driver}", %{driver: driver} do
      draft = by_label("Potion draft A")

      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> fill(draft, "client draft")
      |> press(draft, "Enter")
      |> expect("#drafts > div:first-child input" |> by_css() |> to_have_value("B"))
      |> expect(to_have_value(draft, "client draft"))
      |> expect(to_be_focused(draft))
    end

    @tag driver: driver
    test "Live patches reset an unfocused input with an unchanged server default with #{driver}", %{
      driver: driver
    } do
      draft = by_label("Potion draft A")

      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> fill(draft, "client draft")
      |> click(by_role(:button, name: "Disable first ingredient"))
      |> expect("First ingredient" |> by_label() |> to_be_disabled())
      |> expect(to_have_value(draft, "A"))
    end

    @tag driver: driver
    test "an input-level phx-change sends only that control with #{driver}", %{driver: driver} do
      session = start_test_session(driver)

      session
      |> visit("/live/potions")
      |> fill(by_label("Direct"), "only me")
      |> expect("Input event direct: only me" |> by_text() |> to_be_visible())
      |> expect("Input event has first: false" |> by_text() |> to_be_visible())
      |> expect("Input event target: profile/direct" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "Live target paths use query-decoded input names with #{driver}", %{driver: driver} do
      session = start_test_session(driver)

      session
      |> visit("/live/potions")
      |> fill(by_label("Encoded target"), "value")
      |> expect("Last target: profile/target key" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "a control disabled after editing is omitted from Live submission with #{driver}", %{
      driver: driver
    } do
      session = start_test_session(driver)

      session
      |> visit("/live/potions")
      |> fill(by_label("First ingredient"), "moonstone")
      |> click(by_role(:button, name: "Disable first ingredient"))
      |> click(by_role(:button, name: "Bottle potion", exact: true))
      |> expect("Saved first present: false" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "a Live submitter can navigate and retains its identity with #{driver}", %{
      driver: driver
    } do
      session = start_test_session(driver)

      session
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Bottle and enter chamber"))
      |> expect("The secret chamber is open" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Fluffy.TestServer.base_url() <> "/live/secret-chamber"))
    end

    @tag driver: driver
    test "a normal form submission leaves LiveView through the session backend with #{driver}", %{
      driver: driver
    } do
      session = start_test_session(driver)

      session
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Leave potion lab"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Fluffy.TestServer.base_url() <> "/chamber?from=live-form"))
    end

    @tag driver: driver
    test "phx-trigger-action hands the final form to HTTP navigation with #{driver}", %{
      driver: driver
    } do
      session = start_test_session(driver)

      session
      |> visit("/live/potions")
      |> fill(by_label("Cauldron controlled"), "silver dust")
      |> click(by_role(:button, name: "Send potion over HTTP"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(query: %{"profile[stubborn]" => "silver dust"}, query_mode: :subset))
    end

    @tag driver: driver
    test "an unrelated Live action can trigger an external form with #{driver}", %{
      driver: driver
    } do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Trigger from elsewhere", exact: true))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Fluffy.TestServer.base_url() <> "/chamber?from=external-trigger"))
    end

    @tag driver: driver
    test "phx-trigger-action is committed after a Live patch with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Patch and trigger", exact: true))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Fluffy.TestServer.base_url() <> "/chamber?from=external-trigger"))
    end

    @tag driver: driver
    test "a server redirect wins over phx-trigger-action with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Redirect and trigger", exact: true))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Fluffy.TestServer.base_url() <> "/chamber?from=trigger-redirect"))
    end

    @tag driver: driver
    test "a Live navigation wins over phx-trigger-action with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Navigate and trigger", exact: true))
      |> expect("The secret chamber is open" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Fluffy.TestServer.base_url() <> "/live/secret-chamber"))
    end

    @tag driver: driver
    test "the last simultaneously triggered form wins with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Trigger multiple", exact: true))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Fluffy.TestServer.base_url() <> "/chamber?from=second-trigger"))
    end

    @tag driver: driver
    test "a dynamically inserted triggered form is submitted with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Show trigger form", exact: true))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Fluffy.TestServer.base_url() <> "/chamber?from=dynamic-trigger"))
    end
  end

  test "the Phoenix driver eagerly synchronizes a blur-debounced form mutation" do
    debounced = by_label("Debounced", exact: true)

    :phoenix
    |> start_test_session()
    |> visit("/live/potions")
    |> fill(debounced, "sent by fill")
    |> expect("Last debounced: sent by fill" |> by_text() |> to_be_visible())
    |> expect("Event targets: profile/debounced" |> by_text(exact: true) |> to_be_visible())
    |> blur(debounced)
    |> expect("Event targets: profile/debounced" |> by_text(exact: true) |> to_be_visible())
  end

  test "the Phoenix driver eagerly synchronizes a numeric-debounced form mutation" do
    :phoenix
    |> start_test_session()
    |> visit("/live/potions")
    |> fill(by_label("Timed", exact: true), "sent by fill")
    |> expect("Last target: profile/timed" |> by_text() |> to_be_visible(), timeout: 0)
    |> expect("Event targets: profile/timed" |> by_text() |> to_be_visible(), timeout: 0)
  end

  @tag driver: :playwright
  test "Playwright preserves blur-only LiveView change delivery" do
    debounced = by_label("Debounced", exact: true)

    :playwright
    |> start_test_session()
    |> visit("/live/potions")
    |> fill(debounced, "sent on blur")
    |> expect("Last debounced: none" |> by_text(exact: true) |> to_be_visible(), timeout: 0)
    |> blur(debounced)
    |> expect("Last debounced: sent on blur" |> by_text(exact: true) |> to_be_visible())
  end

  test "the Live driver rejects browser-owned indeterminate checkbox state" do
    session = :phoenix |> start_test_session() |> visit("/live/potions")

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        expect(
          session,
          :checkbox |> by_role(name: "Enabled") |> to_be_checked(indeterminate: true)
        )
      end

    assert error.capability == :indeterminate_checked_state
    assert error.driver == :live
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
