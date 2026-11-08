defmodule Fluffy.Conformance.LiveNavigationTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "commits a Live patch with #{driver}", %{driver: driver} do
      session = live_session(driver)

      session
      |> visit("/live/chamber-map")
      |> click(by_role(:link, name: "Reveal passage", exact: true))
      |> expect(Fluffy.Expect.page_to_have_url("/live/chamber-map?step=patched"))
      |> expect(Fluffy.Expect.page_to_have_url(~r|/live/chamber-map\?step=patched$|))
      |> expect("Map position: patched" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "follows Live navigation with #{driver}", %{driver: driver} do
      session = live_session(driver)

      session
      |> visit("/live/chamber-map")
      |> click(by_role(:link, name: "Secret chamber", exact: true))
      |> expect(Fluffy.Expect.page_to_have_url("/live/secret-chamber"))
      |> expect("The secret chamber is open" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "reclassifies an ordinary Live link destination with #{driver}", %{driver: driver} do
      session = live_session(driver)

      session
      |> visit("/live/chamber-map")
      |> click(by_role(:link, name: "Sleeping chamber", exact: true))
      |> expect(Fluffy.Expect.page_to_have_url("/chamber"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "follows an ordinary redirect returned by a Live event with #{driver}", %{
      driver: driver
    } do
      session = live_session(driver)

      session
      |> visit("/live/chamber-map")
      |> click(by_role(:button, name: "Lull guardian", exact: true))
      |> expect(Fluffy.Expect.page_to_have_url("/chamber"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "follows an asynchronous Live navigation while waiting with #{driver}", %{
      driver: driver
    } do
      session = live_session(driver)

      session
      |> visit("/live/chamber-map?async=true")
      |> expect("The secret chamber is open" |> by_text() |> to_be_visible(), timeout: 1_000)
      |> expect(Fluffy.Expect.page_to_have_url("/live/secret-chamber"))
    end

    @tag driver: driver
    test "follows Live navigation that races the mount render with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/chamber-map?async=mount")
      |> expect(Fluffy.Expect.page_to_have_url("/live/secret-chamber"))
      |> expect("The secret chamber is open" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "follows Live navigation from the connected mount with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/chamber-map?redirect=live")
      |> expect(Fluffy.Expect.page_to_have_url("/live/secret-chamber"))
      |> expect("The secret passage opened" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "follows a redirect from the connected mount to a static page with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/chamber-map?redirect=static")
      |> expect(Fluffy.Expect.page_to_have_url("/chamber"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "clicks on the document a Live navigation landed on after the last read with #{driver}", %{
      driver: driver
    } do
      driver
      |> live_session()
      |> visit("/live/chamber-map?async=return")
      |> await_unread_navigation(driver, "/live/chamber-map?step=returned")
      |> click(by_role(:button, name: "Lull guardian", exact: true))
      |> expect(Fluffy.Expect.page_to_have_url("/chamber"))
    end

    @tag driver: driver
    test "fills on the document a Live navigation landed on after the last read with #{driver}", %{
      driver: driver
    } do
      driver
      |> live_session()
      |> visit("/live/chamber-map?async=return")
      |> await_unread_navigation(driver, "/live/chamber-map?step=returned")
      |> fill(by_label("Map step"), "north")
      |> expect(Fluffy.Expect.page_to_have_url("/live/chamber-map?step=north"))
      |> expect("Map position: north" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "follows a plain link on the document a Live navigation landed on after the last read with #{driver}", %{
      driver: driver
    } do
      driver
      |> live_session()
      |> visit("/live/chamber-map?async=return")
      |> await_unread_navigation(driver, "/live/chamber-map?step=returned")
      |> click(by_role(:link, name: "Chamber from here", exact: true))
      |> expect(Fluffy.Expect.page_to_have_url("/chamber?from=returned"))
    end

    @tag driver: driver
    test "fills a field without phx-change on the document a Live navigation landed on after the last read with #{driver}",
         %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/chamber-map?async=return")
      |> await_unread_navigation(driver, "/live/chamber-map?step=returned")
      |> fill(by_label("Map note"), "north")
      |> expect(Fluffy.Expect.page_to_have_url("/live/chamber-map?step=returned"))
      |> expect("Map note" |> by_label() |> to_have_value("north"))
    end

    @tag driver: driver
    test "clicks inside a nested LiveView on the document a Live navigation landed on after the last read with #{driver}",
         %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/nested?async=return")
      |> await_unread_navigation(driver, "/live/nested?step=returned")
      |> click(by_role(:button, name: "Increment child", exact: true))
      |> expect(Fluffy.Expect.page_to_have_url("/live/nested?step=returned"))
      |> expect("Child count: 1" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "uploads inside a nested LiveView on the document a Live navigation landed on after the last read with #{driver}",
         %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/nested?async=return")
      |> await_unread_navigation(driver, "/live/nested?step=returned")
      |> set_input_files(
        by_label("Child attachment", exact: true),
        Path.expand("../support/fixtures/fluffy-upload.txt", __DIR__)
      )
      |> click(by_role(:button, name: "Upload child attachment", exact: true))
      |> expect(Fluffy.Expect.page_to_have_url("/live/nested?step=returned"))
      |> expect("Child uploaded: fluffy-upload.txt" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "submits a form that appears late on the document a Live navigation landed on after the last read with #{driver}",
         %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/chamber-map?async=return-late")
      |> await_unread_navigation(driver, "/live/chamber-map?step=returned&late=true")
      |> submit(by_css("#map-form"))
      |> expect("Saved step: returned" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "uploads to an input that appears late on the document a Live navigation landed on after the last read with #{driver}",
         %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/nested?async=return-late")
      |> await_unread_navigation(driver, "/live/nested?step=returned&late=true")
      |> set_input_files(
        by_label("Child attachment", exact: true),
        Path.expand("../support/fixtures/fluffy-upload.txt", __DIR__)
      )
      |> click(by_role(:button, name: "Upload child attachment", exact: true))
      |> expect("Child uploaded: fluffy-upload.txt" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "an action whose target a Live navigation removed fails as missing with #{driver}", %{
      driver: driver
    } do
      session =
        driver
        |> live_session()
        |> visit("/live/chamber-map?async=true")
        |> await_unread_navigation(driver, "/live/secret-chamber")

      assert_raise Fluffy.OperationError, ~r/Lull guardian/, fn ->
        click(session, by_role(:button, name: "Lull guardian", exact: true), timeout: 200)
      end
    end

    @tag driver: driver
    test "a press whose page navigates between keydown and keyup is not repeated there with #{driver}", %{
      driver: driver
    } do
      driver
      |> live_session()
      |> visit("/live/keyboard")
      |> press(by_label("Leaving key", exact: true), "Enter")
      |> expect(Fluffy.Expect.page_to_have_url("/live/keyboard?step=left"))
      |> expect("Step: left" |> by_text(exact: true) |> to_be_visible())
      |> expect("Event count: 0" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "a click whose first pushed event navigates is not repeated on the new page with #{driver}", %{
      driver: driver
    } do
      driver
      |> live_session()
      |> visit("/live/chamber-map")
      |> click(by_label("Enter chamber and save", exact: true))
      |> expect(Fluffy.Expect.page_to_have_url("/live/secret-chamber"))
      |> expect("The secret chamber is open" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "follows Live navigation that races the post-action render with #{driver}", %{
      driver: driver
    } do
      session = live_session(driver)

      session
      |> visit("/live/chamber-map")
      |> click(by_role(:button, name: "Enter chamber after event", exact: true))
      |> expect(Fluffy.Expect.page_to_have_url("/live/secret-chamber"))
      |> expect("The secret chamber is open" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "follows a Live patch that arrives after the post-action render with #{driver}", %{
      driver: driver
    } do
      session = live_session(driver)

      session
      |> visit("/live/chamber-map")
      |> click(by_role(:button, name: "Reveal passage after event", exact: true))
      |> expect(Fluffy.Expect.page_to_have_url("/live/chamber-map?step=late-patched"))
      |> expect("Map position: late-patched" |> by_text(exact: true) |> to_be_visible())
    end
  end

  @tag driver: :phoenix
  test "follows a Live redirect when the channel shutdown wins the client-proxy race" do
    session = :phoenix |> live_session() |> visit("/live/chamber-map")
    state = Fluffy.Session.page_state(session)
    {_reference, _topic, proxy_pid} = state.view.proxy
    proxy_reference = Process.monitor(proxy_pid)

    Process.exit(
      state.view.pid,
      {:shutdown, {:live_redirect, %{kind: :push, to: "/live/secret-chamber"}}}
    )

    assert_receive {:DOWN, ^proxy_reference, :process, ^proxy_pid, _reason}

    session
    |> expect(Fluffy.Expect.page_to_have_url("/live/secret-chamber"))
    |> expect("The secret chamber is open" |> by_text() |> to_be_visible())
  end

  @tag driver: :phoenix
  test "a connected-mount redirect loop fails at the redirect limit" do
    session = live_session(:phoenix)

    assert_raise RuntimeError, ~r/exceeded 20 redirects/, fn ->
      visit(session, "/live/chamber-map?redirect=ping")
    end
  end

  @tag driver: :phoenix
  test "an action without timeout budget acts once on the page a navigation landed on" do
    :phoenix
    |> live_session()
    |> visit("/live/chamber-map?async=return")
    |> await_unread_navigation(:phoenix, nil)
    |> click(by_role(:button, name: "Lull guardian", exact: true), timeout: 0)
    |> expect(Fluffy.Expect.page_to_have_url("/chamber"))
  end

  @tag driver: :phoenix
  test "an action without timeout budget whose target a navigation removed fails as missing and leaves the new page" do
    session =
      :phoenix
      |> live_session()
      |> visit("/live/chamber-map?async=true")
      |> await_unread_navigation(:phoenix, nil)

    error =
      assert_raise Fluffy.OperationError, ~r/Lull guardian/, fn ->
        click(session, by_role(:button, name: "Lull guardian", exact: true), timeout: 0)
      end

    refute Exception.message(error) =~ "navigated away"

    session
    |> expect(Fluffy.Expect.page_to_have_url("/live/secret-chamber"))
    |> expect("The secret chamber is open" |> by_text() |> to_be_visible())
  end

  @tag driver: :phoenix
  test "an action without timeout budget acts once on the page a navigation only the view watcher reported landed on" do
    session = :phoenix |> live_session() |> visit("/live/chamber-map")
    state = Fluffy.Session.page_state(session)
    {_reference, _topic, proxy_pid} = state.view.proxy
    proxy_reference = Process.monitor(proxy_pid)
    watcher_reference = Process.monitor(state.watcher)

    Process.exit(state.view.pid, {:shutdown, {:live_redirect, %{kind: :push, to: "/live/secret-chamber"}}})

    assert_receive {:DOWN, ^proxy_reference, :process, ^proxy_pid, _reason}
    assert_receive {:DOWN, ^watcher_reference, :process, _watcher, _reason}

    error =
      assert_raise Fluffy.OperationError, ~r/Lull guardian/, fn ->
        click(session, by_role(:button, name: "Lull guardian", exact: true), timeout: 0)
      end

    refute Exception.message(error) =~ "navigated away"

    session
    |> expect(Fluffy.Expect.page_to_have_url("/live/secret-chamber"))
    |> expect("The secret chamber is open" |> by_text() |> to_be_visible())
  end

  # Waits until the view has navigated away without Fluffy reading it, so the
  # next action still targets the document Fluffy last saw.
  defp await_unread_navigation(session, :phoenix, _url) do
    {_reference, _topic, proxy_pid} = Fluffy.Session.page_state(session).view.proxy
    proxy_reference = Process.monitor(proxy_pid)
    assert_receive {:DOWN, ^proxy_reference, :process, ^proxy_pid, _reason}, 1_000
    session
  end

  defp await_unread_navigation(session, :playwright, url), do: expect(session, Fluffy.Expect.page_to_have_url(url))

  defp live_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
