defmodule Fluffy.Conformance.LiveFormTest do
  use Fluffy.Support.Case, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Support.HTTPFixtures
  alias Fluffy.Support.Server

  test "Live reset buttons do not reset fields and still dispatch server events" do
    session = :phoenix |> start_test_session() |> visit("/live/potions")

    session
    |> fill(by_label("Reset name"), "changed")
    |> uncheck(by_label("Reset choice"))
    |> click(by_role(:button, name: "Native reset", exact: true))
    |> expect(to_have_value(by_label("Reset name"), "changed"))
    |> expect(not_(to_be_checked(by_label("Reset choice"))))
    |> click(by_role(:button, name: "Reset with server event", exact: true))
    |> expect("#drafts > div:first-child input" |> by_css() |> to_have_value("B"))
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "String.Chars values reach LiveView change events as literal strings with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> fill(by_label("First ingredient"), ~D[2026-09-30])
      |> expect("Last first: 2026-09-30" |> by_text() |> to_be_visible())
      |> Fluffy.PhoenixTest.fill_in("Final ingredient", with: %Fluffy.Support.FormValue{value: "<tag>&"})
      |> then(fn %{session: session} -> session end)
      |> expect("Last last: custom:<tag>&" |> by_text() |> to_be_visible())
      |> select_option(by_label("Potion colours"), [%{value: :blue}, %{value: :green}])
      |> expect("Potion colours" |> by_label() |> to_have_values(["green", "blue"]))
    end

    @tag driver: driver
    test "unchanged sticky LiveView renders preserve entered form values with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions?sticky=true")
      |> fill(by_label("Uncontrolled email"), "hermione@hogwarts.example")
      |> fill(by_label("Uncontrolled name"), "Hermione")
      |> expect("Uncontrolled email" |> by_label() |> to_have_value("hermione@hogwarts.example"))
      |> expect("Uncontrolled name" |> by_label() |> to_have_value("Hermione"))
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
      |> expect("Last target: wizard/first" |> by_text() |> to_be_visible())
      |> expect("Unused first: false" |> by_text() |> to_be_visible())
      |> expect("Unused last: true" |> by_text() |> to_be_visible())
      |> fill(last, "phoenix feather")
      |> expect(to_have_value(last, "phoenix feather"))
      |> expect("#hidden-version" |> by_css() |> to_have_value("version-3"))
      |> expect("Last target: wizard/last" |> by_text() |> to_be_visible())
      |> expect("Unused first: false" |> by_text() |> to_be_visible())
      |> expect("Unused last: false" |> by_text() |> to_be_visible())
      |> fill(stubborn, "silver dust")
      |> expect(to_have_value(stubborn, if(driver == :playwright, do: "silver dust", else: "server-4")))
      |> fill(last, "dragon scale")
      |> expect(to_have_value(stubborn, "server-5"))
      |> expect("Last first: moonstone" |> by_text() |> to_be_visible())
      |> expect("Last last: dragon scale" |> by_text() |> to_be_visible())
      |> expect("Last version: version-4" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "checking a radio marks only that radio used, even after a patch shifts its group with #{driver}", %{
      driver: driver
    } do
      driver
      |> start_test_session()
      |> visit("/live/used-shift")
      |> click(by_role(:radio, name: "c"))
      |> expect("Changed: true" |> by_text() |> to_be_visible())
      |> fill(by_label("Other"), "x")
      |> expect("key:other" |> by_text(exact: true) |> to_be_visible())
      |> expect("key:_unused_note" |> by_text(exact: true) |> to_be_visible())
      |> expect("key:_unused_choice" |> by_text(exact: true) |> to_have_count(0))
    end

    @tag driver: driver
    test "a submit marks every form control used for later changes with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/submit-used")
      |> fill(by_label("Name"), "Hermione")
      |> expect("Email is required" |> by_text() |> to_have_count(0))
      |> click(by_role(:button, name: "Save"))
      |> expect("Submits: 1" |> by_text() |> to_be_visible())
      |> expect("Email is required" |> by_text() |> to_be_visible())
      |> fill(by_label("Name"), "Hermione Granger")
      |> expect(to_have_value(by_label("Name"), "Hermione Granger"))
      |> expect("Email is required" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "a submit blocked by an upload entry error still marks the form used with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/submit-used?upload=oversized")
      |> fill(by_label("Name"), "Hermione")
      |> set_input_files(by_label("Attachment"), Path.expand("../support/fixtures/fluffy-upload.txt", __DIR__))
      |> expect("Upload errors: 1" |> by_text() |> to_be_visible())
      |> click(by_role(:button, name: "Save"))
      |> expect("Submits: 0" |> by_text() |> to_be_visible())
      |> fill(by_label("Name"), "Hermione Granger")
      |> expect(to_have_value(by_label("Name"), "Hermione Granger"))
      |> expect("Email is required" |> by_text() |> to_be_visible())
    end

    # The form also has an HTTP action, which a cancelled submit never reaches.
    @tag driver: driver
    test "submit sends a phx-submit form to LiveView only with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> fill(by_label("Row 0"), "aconite")
      |> submit(by_css("#wizard-form"), timeout: 2_000)
      |> expect("Saved rows: aconite, belladonna, cinder" |> by_text() |> to_be_visible())
      |> expect(page_to_have_url(&(URI.parse(&1).path == "/live/potions")))
    end

    for status <- [204, 205] do
      @tag driver: driver
      # LiveView's client disconnects as the form submits, so the kept page stays inert.
      test "a #{status} response to an HTTP form keeps the disconnected LiveView page with #{driver}", %{
        driver: driver
      } do
        fixture = HTTPFixtures.register(%{status: unquote(status)})

        driver
        |> start_test_session()
        |> visit("/live/no-content?" <> URI.encode_query(to: HTTPFixtures.path(fixture, "/save")))
        |> click(by_role(:button, name: "Increment"))
        |> expect("Count: 1" |> by_text() |> to_be_visible())
        |> fill(by_label("Note"), "edited")
        |> submit(by_css("#http-form"), timeout: 2_000)
        |> expect("Note" |> by_label() |> to_have_value("edited"))
        |> expect(page_to_have_url(&(URI.parse(&1).path == "/live/no-content")))
        |> click(by_role(:button, name: "Increment"))
        |> expect("Count: 1" |> by_text() |> to_be_visible())

        assert [%{method: "POST", body: "note=edited"}] = HTTPFixtures.requests(fixture)
      end
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
      |> expect("Event targets: wizard/enabled" |> by_text() |> to_be_visible())
      |> check(checkbox)
      |> expect("Checkbox clicks: 1" |> by_text() |> to_be_visible())
      |> uncheck(checkbox)
      |> expect("Checkbox clicks: 2" |> by_text() |> to_be_visible())
      |> expect("Event targets: wizard/enabled, wizard/enabled" |> by_text() |> to_be_visible())
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
    test "keyed reorder preserves text only with browser focus using #{driver}", %{driver: driver} do
      draft = by_label("Potion draft A")

      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> fill(draft, "client draft")
      |> press(draft, "Enter")
      |> expect("#drafts > div:first-child input" |> by_css() |> to_have_value("B"))
      |> expect(to_have_value(draft, if(driver == :playwright, do: "client draft", else: "A")))
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
      |> expect("Input event target: wizard/direct" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "Live target paths use query-decoded input names with #{driver}", %{driver: driver} do
      session = start_test_session(driver)

      session
      |> visit("/live/potions")
      |> fill(by_label("Encoded target"), "value")
      |> expect("Last target: wizard/target key" |> by_text() |> to_be_visible())
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
      |> expect(Fluffy.Expect.page_to_have_url(Server.base_url() <> "/live/secret-chamber"))
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
      |> expect(Fluffy.Expect.page_to_have_url(Server.base_url() <> "/chamber?from=live-form"))
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
      |> expect(
        Fluffy.Expect.page_to_have_url(fn url ->
          URI.decode_query(URI.parse(url).query)["wizard[stubborn]"] ==
            if(driver == :playwright, do: "silver dust", else: "server-2")
        end)
      )
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
      |> expect(Fluffy.Expect.page_to_have_url(Server.base_url() <> "/chamber?from=external-trigger"))
    end

    @tag driver: driver
    test "phx-trigger-action is committed after a Live patch with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Patch and trigger", exact: true))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Server.base_url() <> "/chamber?from=external-trigger"))
    end

    @tag driver: driver
    test "a server redirect wins over phx-trigger-action with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Redirect and trigger", exact: true))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Server.base_url() <> "/chamber?from=trigger-redirect"))
    end

    @tag driver: driver
    test "a Live navigation wins over phx-trigger-action with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Navigate and trigger", exact: true))
      |> expect("The secret chamber is open" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Server.base_url() <> "/live/secret-chamber"))
    end

    @tag driver: driver
    test "the last simultaneously triggered form wins with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Trigger multiple", exact: true))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Server.base_url() <> "/chamber?from=second-trigger"))
    end

    @tag driver: driver
    test "a dynamically inserted triggered form is submitted with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> click(by_role(:button, name: "Show trigger form", exact: true))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Server.base_url() <> "/chamber?from=dynamic-trigger"))
    end

    @tag driver: driver
    test "a form triggered on the connected render is submitted with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/trigger-on-connect?identity=hermione")
      |> expect(Fluffy.Expect.page_to_have_url(Server.base_url() <> "/session/show"))
      |> expect("Static identity: hermione" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "a form triggered on the connected render beats a navigation sent after the join with #{driver}",
         %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/trigger-on-connect?identity=hermione&then=navigate")
      |> expect(Fluffy.Expect.page_to_have_url(Server.base_url() <> "/session/show"))
      |> expect("Static identity: hermione" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "a form triggered on the connected render can leave for another origin with #{driver}", %{driver: driver} do
      session = start_test_session(driver)

      # A browser really loads the external page, so Playwright stubs its host.
      if driver == :playwright do
        Fluffy.Playwright.route(session, "https://ministry.example/**", fn route ->
          PlaywrightEx.Route.fulfill!(route, content_type: "text/html", body: "<h1>Floo to the Ministry</h1>")
        end)
      end

      session
      |> visit("/live/trigger-on-connect?identity=hermione&trigger=ministry")
      |> expect(Fluffy.Expect.page_to_have_url("https://ministry.example/floo"))
    end

    @tag driver: driver
    test "a form triggered on the dead render only is not submitted with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/trigger-on-connect?identity=hermione&trigger=dead")
      |> expect("Floo powder for hermione" |> by_text() |> to_be_visible())
      # The LiveView client disconnects before it submits a triggered form, so
      # the view only answers if it was not submitted.
      |> click(by_role(:button, name: "Lumos"))
      |> expect("Wand lit" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(~r|/live/trigger-on-connect\?|))
    end

    # An action waits for its target through the form's navigation.
    @tag driver: driver
    test "a form triggered from handle_info is submitted with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/trigger-on-connect?identity=hermione&trigger=later")
      |> click(by_role(:button, name: "Trigger later"))
      |> click(by_text("Static identity: hermione"))
      |> expect(Fluffy.Expect.page_to_have_url(Server.base_url() <> "/session/show"))
    end

    # The form's relative action resolves from the patched URL.
    @tag driver: driver
    test "a form triggered in handle_params after a server push_patch is submitted with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/trigger-on-connect?identity=hermione&trigger=later&form=relative")
      |> click(by_role(:button, name: "Patch later"))
      |> expect(Fluffy.Expect.page_to_have_url(Server.base_url() <> "/session/show"))
      |> expect("Static identity: hermione" |> by_text() |> to_be_visible())
    end

    # LiveView's client unloads before it submits a triggered form, so a
    # download leaves an inert page that does not submit the form again.
    @tag driver: driver
    test "a triggered form that downloads leaves the page inert with #{driver}", %{driver: driver} do
      session = start_test_session(driver)
      pending = wait_for(session, Fluffy.Event.download())

      session =
        session
        |> visit("/live/trigger-on-connect?identity=hermione&trigger=later&form=map")
        |> click(by_role(:button, name: "Trigger later"))
        # Phoenix reads the pushed render as the expectation waits for it.
        |> expect("I solemnly swear that I am up to no good" |> by_text() |> to_be_visible())

      download = await(pending)
      assert download.suggested_filename == "marauders_map.csv"
      assert Fluffy.Download.read(download) == "student\nhermione\n"

      session = expect(session, "Floo powder for hermione" |> by_text() |> to_be_visible())

      if driver == :phoenix do
        session
        |> click(by_role(:button, name: "Lumos"))
        |> expect("Wand lit" |> by_text() |> to_have_count(0))
      end
    end
  end

  test "a form triggered on every connected render fails at the redirect limit" do
    session = start_test_session(:phoenix)

    assert_raise RuntimeError, ~r/exceeded 20 redirects/, fn ->
      visit(session, "/live/trigger-on-connect?trigger=loop")
    end
  end

  # In a browser the form is already submitted, whatever the test's timeout.
  test "an expectation without timeout budget follows a form the view triggered" do
    session = :phoenix |> start_test_session() |> visit("/live/trigger-on-connect?identity=hermione&trigger=later")
    view = Fluffy.Session.page_state(session).view.pid
    send(view, :trigger)
    # Returns once the view handled the message.
    :sys.get_state(view)

    expect(session, Fluffy.Expect.page_to_have_url(Server.base_url() <> "/session/show"), timeout: 0)
  end

  test "the Phoenix driver eagerly synchronizes a blur-debounced form mutation" do
    debounced = by_label("Debounced", exact: true)

    :phoenix
    |> start_test_session()
    |> visit("/live/potions")
    |> fill(debounced, "sent by fill")
    |> expect("Last debounced: sent by fill" |> by_text() |> to_be_visible())
    |> expect("Event targets: wizard/debounced" |> by_text(exact: true) |> to_be_visible())
  end

  test "the Phoenix driver eagerly synchronizes a numeric-debounced form mutation" do
    :phoenix
    |> start_test_session()
    |> visit("/live/potions")
    |> fill(by_label("Timed", exact: true), "sent by fill")
    |> expect("Last target: wizard/timed" |> by_text() |> to_be_visible(), timeout: 0)
    |> expect("Event targets: wizard/timed" |> by_text() |> to_be_visible(), timeout: 0)
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
      base_url: Server.base_url(),
      endpoint: Fluffy.Support.Web.Endpoint
    )
  end
end
