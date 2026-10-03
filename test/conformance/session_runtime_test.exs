defmodule Fluffy.Conformance.SessionRuntimeTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Backend
  alias Fluffy.Page
  alias Fluffy.Session

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "alternating documents preserves each session's input state with #{driver}" do
      first =
        session_for_html(unquote(driver), """
        <label>Name <input></label>
        <label>Colour <select><option>Red</option><option>Blue</option></select></label>
        """)

      second =
        session_for_html(unquote(driver), """
        <section>
          <label>Colour <select><option>Green</option><option>Yellow</option></select></label>
          <label>Name <textarea></textarea></label>
        </section>
        """)

      fill(first, by_label("Name"), "Ada")
      select_option(first, by_label("Colour"), "Blue")
      fill(second, by_label("Name"), "Grace")
      select_option(second, by_label("Colour"), "Yellow")

      expect(first, "Name" |> by_label() |> to_have_value("Ada"))
      expect(second, "Name" |> by_label() |> to_have_value("Grace"))
      expect(first, "option:checked" |> by_css() |> by_text("Blue", exact: true) |> to_have_count(1))
      expect(second, "option:checked" |> by_css() |> by_text("Yellow", exact: true) |> to_have_count(1))
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "existing handles see navigation and actions with #{driver}" do
      session = start_session(unquote(driver))
      page = Session.handle(session)
      visit(session, "/live/three-heads")
      click(session, by_role(:button, name: "Play the flute"))
      expect(session, "Sleeping heads: 1" |> by_text() |> to_be_visible())
      assert Session.handle(session) == page
      assert Page.url(page) =~ "/live/three-heads"

      visit(session, "/chamber")
      assert Session.handle(session) == page
      assert Page.url(page) =~ "/chamber"
      assert Page.status(page) == 200
      expect(session, "The guardian sleeps" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "closing one #{driver} session leaves another usable" do
      first = unquote(driver) |> start_session() |> visit("/live/three-heads")
      second = unquote(driver) |> start_session() |> visit("/live/three-heads")
      Backend.close_session(first)
      assert_raise ArgumentError, ~r/session is closed/, fn -> Session.current_driver(first) end
      click(second, by_role(:button, name: "Play the flute"))
      expect(second, "Sleeping heads: 1" |> by_text() |> to_be_visible())
    end
  end

  @tag driver: :playwright
  test "page selections are independent and closed identities cannot be reused" do
    session = :playwright |> start_session() |> visit("/chamber")
    main = current_page(session)
    other_session = session |> switch_page(new_page(session)) |> visit("/live/three-heads")
    other = current_page(other_session)

    click(other_session, by_role(:button, name: "Play the flute"))
    assert current_page(session) == main
    assert current_page(other_session) == other
    expect(session, "The guardian sleeps" |> by_text() |> to_be_visible())
    expect(other_session, "Sleeping heads: 1" |> by_text() |> to_be_visible())

    foreign = :playwright |> start_session() |> current_page()
    assert_raise ArgumentError, ~r/different session/, fn -> switch_page(session, foreign) end

    close_page(other_session)
    assert_raise ArgumentError, ~r/closed/, fn -> Page.url(other) end
    assert_raise ArgumentError, ~r/closed/, fn -> click(other_session, by_css("button")) end
    assert current_page(switch_page(other_session, main)) == main

    replacement = new_page(session)
    refute replacement == other
    assert_raise ArgumentError, ~r/closed/, fn -> switch_page(session, other) end
    assert Enum.sort(pages(session)) == Enum.sort([main, replacement])
  end

  @tag driver: :playwright
  test "native page closure invalidates handles without closing other pages" do
    session = start_session(:playwright)
    other = switch_page(session, new_page(session))
    closed = current_page(other)
    state = Session.page_state(other)
    context = Session.context(other)
    assert {:ok, _} = PlaywrightEx.Page.close(state.page_id, connection: context.connection, timeout: context.timeout)
    assert_raise ArgumentError, ~r/closed/, fn -> Page.url(closed) end
    visit(session, "/chamber")
    expect(session, "The guardian sleeps" |> by_text() |> to_be_visible())
  end

  for close <- [:fluffy, :native] do
    @tag driver: :playwright
    test "closing the opener through #{close} clears the child's opener" do
      fixture =
        Fluffy.TestHTTPFixtures.register(%{
          body: "<html><body><a href='about:blank' target='_blank'>Open</a></body></html>"
        })

      session =
        :playwright
        |> start_session()
        |> visit(Fluffy.TestHTTPFixtures.path(fixture))

      pending = wait_for(session, Fluffy.Event.popup())
      click(session, by_role(:link, name: "Open"))
      opener = current_page(session)
      child = switch_page(session, await(pending))
      expect(child, page_to_have_opener(opener))

      case unquote(close) do
        :fluffy ->
          close_page(session)

        :native ->
          assert {:ok, _} =
                   PlaywrightEx.Page.close(Session.page_state(session).page_id,
                     connection: Session.context(session).connection,
                     timeout: Session.context(session).timeout
                   )
      end

      assert_eventually(fn -> Page.opener(current_page(child)) == nil end)
      expect(child, page_to_have_opener(nil))
      expect(child, not_(page_to_have_opener(opener)))
      assert_raise ArgumentError, ~r/closed/, fn -> Page.url(opener) end

      # Creating a new page must not restore a closed opener.
      new_page(child)
      expect(child, page_to_have_opener(nil))
    end
  end

  @tag driver: :phoenix
  test "in-process native callbacks retain the caller process" do
    caller = self()
    session = :phoenix |> start_session() |> visit("/live/three-heads")

    unwrap(session, fn view ->
      assert self() == caller
      assert Phoenix.LiveViewTest.render(view) =~ "Sleeping heads: 0"
    end)
  end

  @tag driver: :playwright
  test "native browser pages are discovered without a Fluffy event wait" do
    session = start_session(:playwright)
    main = current_page(session)
    context = Session.context(session)

    assert {:ok, browser_page} =
             PlaywrightEx.BrowserContext.new_page(context.context_id,
               connection: context.connection,
               timeout: context.timeout
             )

    assert_eventually(fn -> length(pages(session)) == 2 end)
    [discovered] = pages(session) -- [main]

    session |> switch_page(discovered) |> visit("/chamber")
    assert Page.url(discovered) =~ "/chamber"
    assert Page.status(discovered) == 200
    assert current_page(session) == main

    assert {:ok, _} =
             PlaywrightEx.Page.close(browser_page.guid, connection: context.connection, timeout: context.timeout)

    assert_eventually(fn -> pages(session) == [main] end)
    assert_raise ArgumentError, ~r/closed/, fn -> Page.url(discovered) end
  end

  @tag driver: :playwright
  test "native context closure closes the session runtime" do
    session = start_session(:playwright)
    context = Session.context(session)
    runtime = session.runtime
    monitor = Process.monitor(runtime)

    assert {:ok, _} =
             PlaywrightEx.BrowserContext.close(context.context_id,
               connection: context.connection,
               timeout: context.timeout
             )

    assert_receive {:DOWN, ^monitor, :process, ^runtime, :normal}, 5_000
    assert_raise ArgumentError, ~r/session is closed/, fn -> pages(session) end
  end

  @tag driver: :playwright
  test "an unmanaged browser session closes its context when its owner exits" do
    parent = self()

    owner =
      spawn(fn ->
        session = session_for_html(:playwright, "<p>Owned page</p>")
        send(parent, {:started, session.runtime, Session.context(session)})

        receive do
          :finish -> :ok
        end
      end)

    assert_receive {:started, runtime, context}, 5_000
    monitor = Process.monitor(runtime)
    send(owner, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^runtime, :normal}, 5_000

    assert {:error, _} =
             PlaywrightEx.BrowserContext.cookies(context.context_id, connection: context.connection, timeout: 100)
  end

  defp assert_eventually(fun, attempts \\ 100)
  defp assert_eventually(fun, 0), do: assert(fun.())

  defp assert_eventually(fun, attempts) do
    if !fun.() do
      Process.sleep(10)
      assert_eventually(fun, attempts - 1)
    end
  end
end
