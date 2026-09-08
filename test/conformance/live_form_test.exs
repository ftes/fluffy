defmodule Fluffy.Conformance.LiveFormTest do
  use Fluffy.TestCase, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Page

  for driver <- [:phoenix, :playwright] do
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
      |> expect(value(first, "moonstone"))
      |> expect(value(by_css("#hidden-version"), "version-2"))
      |> expect(visible(by_text("Last target: profile/first")))
      |> expect(visible(by_text("Unused first: false")))
      |> expect(visible(by_text("Unused last: true")))
      |> fill(last, "phoenix feather")
      |> expect(value(last, "phoenix feather"))
      |> expect(value(by_css("#hidden-version"), "version-3"))
      |> expect(visible(by_text("Last target: profile/last")))
      |> expect(visible(by_text("Unused first: false")))
      |> expect(visible(by_text("Unused last: false")))
      |> fill(stubborn, "silver dust")
      |> expect(value(stubborn, "silver dust"))
      |> fill(last, "dragon scale")
      |> expect(value(stubborn, "server-5"))
      |> expect(visible(by_text("Last first: moonstone")))
      |> expect(visible(by_text("Last last: dragon scale")))
      |> expect(visible(by_text("Last version: version-4")))
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
        |> expect(count(by_label("Row 1"), 0))
        |> click(by_role(:button, name: "Bottle potion", exact: true))

      session
      |> expect(visible(by_text("Saved rows: aconite, cinder")))
      |> expect(visible(by_text("Saved drop is only empty: true")))
      |> expect(visible(by_text("Saved external: outside")))
      |> expect(visible(by_text("Saved commit: save")))
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
      |> expect(checked(enabled))
      |> select_option(colours, ["blue", "green"])
      |> expect(values(colours, ["green", "blue"]))
      |> uncheck(enabled)
      |> expect(not_(checked(enabled)))
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
      |> expect(visible(by_text("Checkbox clicks: 1")))
      |> expect(visible(by_text("Event targets: profile/enabled")))
      |> check(checkbox)
      |> expect(visible(by_text("Checkbox clicks: 1")))
      |> uncheck(checkbox)
      |> expect(visible(by_text("Checkbox clicks: 2")))
      |> expect(visible(by_text("Event targets: profile/enabled, profile/enabled")))
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
      |> expect(value(by_label("First ingredient"), "moonstone"))
      |> click(by_role(:button, name: "Bottle potion", exact: true))
      |> expect(visible(by_text("Saved dynamic controls: true")))
    end

    @tag driver: driver
    test "Live keyed reorder and replacement reset the unfocused input with #{driver}", %{driver: driver} do
      draft = by_label("Potion draft A")

      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> fill(draft, "client draft")
      |> click(by_role(:button, name: "Reorder potion drafts"))
      |> expect(value(by_css("#drafts > div:first-child input"), "B"))
      |> expect(value(draft, "A"))
      |> fill(draft, "client draft")
      |> click(by_role(:button, name: "Replace potion draft A"))
      |> expect(value(draft, "A"))
    end

    @tag driver: driver
    test "Live keyed reorder preserves the focused input with #{driver}", %{driver: driver} do
      draft = by_label("Potion draft A")

      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> fill(draft, "client draft")
      |> press(draft, "Enter")
      |> expect(value(by_css("#drafts > div:first-child input"), "B"))
      |> expect(value(draft, "client draft"))
      |> expect(focused(draft))
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
      |> expect(disabled(by_label("First ingredient")))
      |> expect(value(draft, "A"))
    end

    @tag driver: driver
    test "an input-level phx-change sends only that control with #{driver}", %{driver: driver} do
      session = start_test_session(driver)

      session
      |> visit("/live/potions")
      |> fill(by_label("Direct"), "only me")
      |> expect(visible(by_text("Input event direct: only me")))
      |> expect(visible(by_text("Input event has first: false")))
      |> expect(visible(by_text("Input event target: profile/direct")))
    end

    @tag driver: driver
    test "Live target paths use query-decoded input names with #{driver}", %{driver: driver} do
      session = start_test_session(driver)

      session
      |> visit("/live/potions")
      |> fill(by_label("Encoded target"), "value")
      |> expect(visible(by_text("Last target: profile/target key")))
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
      |> expect(visible(by_text("Saved first present: false")))
    end

    @tag driver: driver
    test "a Live submitter can navigate and retains its identity with #{driver}", %{
      driver: driver
    } do
      session = start_test_session(driver)

      session
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Bottle and enter chamber"))
      |> expect(visible(by_text("The secret chamber is open")))
      |> expect(Page.to_have_url(Fluffy.TestServer.base_url() <> "/live/secret-chamber"))
    end

    @tag driver: driver
    test "a normal form submission leaves LiveView through the session backend with #{driver}", %{
      driver: driver
    } do
      session = start_test_session(driver)

      session
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Leave potion lab"))
      |> expect(visible(by_text("The guardian sleeps")))
      |> expect(Page.to_have_url(Fluffy.TestServer.base_url() <> "/chamber?from=live-form"))
    end

    @tag driver: driver
    test "phx-trigger-action hands the final form to HTTP navigation with #{driver}", %{
      driver: driver
    } do
      session = start_test_session(driver)

      session
      |> visit("/live/potions")
      |> fill(by_label("First ingredient"), "moonstone")
      |> click(by_role(:button, name: "Send potion over HTTP"))
      |> expect(visible(by_text("The guardian sleeps")))
    end

    @tag driver: driver
    test "an unrelated Live action can trigger an external form with #{driver}", %{
      driver: driver
    } do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Trigger from elsewhere", exact: true))
      |> expect(visible(by_text("The guardian sleeps")))
      |> expect(Page.to_have_url(Fluffy.TestServer.base_url() <> "/chamber?from=external-trigger"))
    end

    @tag driver: driver
    test "phx-trigger-action is committed after a Live patch with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Patch and trigger", exact: true))
      |> expect(visible(by_text("The guardian sleeps")))
      |> expect(Page.to_have_url(Fluffy.TestServer.base_url() <> "/chamber?from=external-trigger"))
    end

    @tag driver: driver
    test "a server redirect wins over phx-trigger-action with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Redirect and trigger", exact: true))
      |> expect(visible(by_text("The guardian sleeps")))
      |> expect(Page.to_have_url(Fluffy.TestServer.base_url() <> "/chamber?from=trigger-redirect"))
    end

    @tag driver: driver
    test "a Live navigation wins over phx-trigger-action with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Navigate and trigger", exact: true))
      |> expect(visible(by_text("The secret chamber is open")))
      |> expect(Page.to_have_url(Fluffy.TestServer.base_url() <> "/live/secret-chamber"))
    end

    @tag driver: driver
    test "the last simultaneously triggered form wins with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Trigger multiple", exact: true))
      |> expect(visible(by_text("The guardian sleeps")))
      |> expect(Page.to_have_url(Fluffy.TestServer.base_url() <> "/chamber?from=second-trigger"))
    end

    @tag driver: driver
    test "a dynamically inserted triggered form is submitted with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Show trigger form", exact: true))
      |> expect(visible(by_text("The guardian sleeps")))
      |> expect(Page.to_have_url(Fluffy.TestServer.base_url() <> "/chamber?from=dynamic-trigger"))
    end
  end

  test "the Phoenix driver eagerly synchronizes a blur-debounced form mutation" do
    debounced = by_label("Debounced", exact: true)

    :phoenix
    |> start_test_session()
    |> visit("/live/potions")
    |> fill(debounced, "sent by fill")
    |> expect(visible(by_text("Last debounced: sent by fill")))
    |> expect(visible(by_text("Event targets: profile/debounced", exact: true)))
    |> blur(debounced)
    |> expect(visible(by_text("Event targets: profile/debounced", exact: true)))
  end

  test "the Phoenix driver eagerly synchronizes a numeric-debounced form mutation" do
    :phoenix
    |> start_test_session()
    |> visit("/live/potions")
    |> fill(by_label("Timed", exact: true), "sent by fill")
    |> expect(visible(by_text("Last target: profile/timed")), timeout: 0)
    |> expect(visible(by_text("Event targets: profile/timed")), timeout: 0)
  end

  @tag driver: :playwright
  test "Playwright preserves blur-only LiveView change delivery" do
    debounced = by_label("Debounced", exact: true)

    :playwright
    |> start_test_session()
    |> visit("/live/potions")
    |> fill(debounced, "sent on blur")
    |> expect(visible(by_text("Last debounced: none", exact: true)), timeout: 0)
    |> blur(debounced)
    |> expect(visible(by_text("Last debounced: sent on blur", exact: true)))
  end

  test "the Live driver rejects browser-owned indeterminate checkbox state" do
    session = :phoenix |> start_test_session() |> visit("/live/potions")

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        expect(
          session,
          checked(by_role(:checkbox, name: "Enabled"), indeterminate: true)
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
