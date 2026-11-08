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
    test "follows a plain link on the document a Live patch changed after the last read with #{driver}", %{
      driver: driver
    } do
      driver
      |> live_session()
      |> visit("/live/chamber-map?async=patch")
      |> await_unread_patches(driver, 1, "/live/chamber-map?step=late-patched")
      |> click(by_role(:link, name: "Chamber from here", exact: true))
      |> expect(Fluffy.Expect.page_to_have_url("/chamber?from=late-patched"))
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
  test "an action on views that keep navigating to each other fails at the redirect limit" do
    # Each view navigates as it connects, so the action never finds its target
    # and follows each navigation instead.
    assert_raise RuntimeError, ~r/exceeded 20 redirects/, fn ->
      :phoenix
      |> live_session()
      |> visit("/live/chamber-map?async=loop")
      |> click(by_role(:button, name: "Missing", exact: true), timeout: 10_000)
    end
  end

  @tag driver: :phoenix
  test "an action's retry counts its redirect toward those of the page it follows" do
    # A visit follows the page's 20 connected-mount redirects within the limit.
    :phoenix
    |> live_session()
    |> visit("/live/chamber-map?redirect=chain-20")
    |> expect(Fluffy.Expect.page_to_have_url("/live/chamber-map?redirect=chain-0"))

    session =
      :phoenix
      |> live_session()
      |> visit("/live/chamber-map?async=chain")
      |> await_unread_navigation(:phoenix, nil)

    assert_raise RuntimeError, ~r/exceeded 20 redirects/, fn ->
      fill(session, by_label("Map note"), "north")
    end
  end

  @tag driver: :phoenix
  test "the next action follows a navigation only the view watcher reported after a retry failed before leaving the page" do
    session = :phoenix |> live_session() |> visit("/live/chamber-map")
    state = Fluffy.Session.page_state(session)
    {_reference, _topic, proxy_pid} = state.view.proxy
    proxy_reference = Process.monitor(proxy_pid)
    watcher_reference = Process.monitor(state.watcher)

    # The destination's HTTP redirects loop, so following it fails before the
    # session leaves the page.
    Process.exit(state.view.pid, {:shutdown, {:live_redirect, %{kind: :push, to: "/redirect/loop"}}})

    assert_receive {:DOWN, ^proxy_reference, :process, ^proxy_pid, _reason}
    assert_receive {:DOWN, ^watcher_reference, :process, _watcher, _reason}

    for _attempt <- 1..2 do
      assert_raise RuntimeError, ~r/exceeded 20 redirects at .*\/redirect\/loop/, fn ->
        fill(session, by_label("Map note"), "north")
      end
    end
  end

  # Each navigation used to retry the expectation with the time left, and once
  # none was left, kept retrying it without end.
  @tag driver: :phoenix
  @tag timeout: 20_000
  test "an expectation on views that keep navigating to each other fails at the redirect limit" do
    session = :phoenix |> live_session() |> visit("/live/chamber-map?async=loop")

    assert_raise RuntimeError, ~r/exceeded 20 redirects/, fn ->
      expect(session, Fluffy.Expect.page_to_have_url("/nowhere"), timeout: 5_000)
    end
  end

  @tag driver: :phoenix
  test "an action without timeout budget fails on a navigation and leaves it for the next call" do
    session =
      :phoenix
      |> live_session()
      |> visit("/live/chamber-map?async=return")
      |> await_unread_navigation(:phoenix, nil)

    {reference, _topic, _proxy_pid} = Fluffy.Session.page_state(session).view.proxy

    assert_raise Fluffy.OperationError, ~r/navigated away before the action reached it/, fn ->
      click(session, by_role(:button, name: "Lull guardian", exact: true), timeout: 0)
    end

    {:messages, messages} = Process.info(self(), :messages)
    assert Enum.any?(messages, &match?({^reference, {:redirect, _topic, %{to: "/live/chamber-map?step=returned"}}}, &1))

    session
    |> expect(Fluffy.Expect.page_to_have_url("/live/chamber-map?step=returned"))
    |> expect("Map position: returned" |> by_text(exact: true) |> to_be_visible())
  end

  @tag driver: :phoenix
  test "a LiveView whose connection LiveView rejects fails with the rejection instead of redirecting to itself" do
    session = live_session(:phoenix)

    assert_raise RuntimeError, ~r/rejected the connection to .*\/unrouted-live as stale or unauthorized/, fn ->
      visit(session, "/unrouted-live")
    end
  end

  @tag driver: :phoenix
  test "an action that follows a navigation counts the navigation toward its timeout" do
    session =
      :phoenix
      |> live_session()
      |> visit("/live/chamber-map?async=return-slow")
      |> await_unread_navigation(:phoenix, nil)

    # Connecting the new view takes 600ms, longer than the action's timeout, so
    # the action makes one attempt there without waiting for the form it
    # renders 150ms after connecting.
    error =
      assert_raise Fluffy.OperationError, ~r/Map step/, fn ->
        fill(session, by_label("Map step", exact: true), "lost", timeout: 300)
      end

    refute Exception.message(error) =~ "navigated away"
  end

  @tag driver: :phoenix
  test "an action without timeout budget fails on a navigation only the view watcher reported and leaves it for the next call" do
    session = :phoenix |> live_session() |> visit("/live/chamber-map")
    state = Fluffy.Session.page_state(session)
    {_reference, _topic, proxy_pid} = state.view.proxy
    proxy_reference = Process.monitor(proxy_pid)
    watcher_reference = Process.monitor(state.watcher)

    Process.exit(state.view.pid, {:shutdown, {:live_redirect, %{kind: :push, to: "/live/secret-chamber"}}})

    assert_receive {:DOWN, ^proxy_reference, :process, ^proxy_pid, _reason}
    assert_receive {:DOWN, ^watcher_reference, :process, _watcher, _reason}

    assert_raise Fluffy.OperationError, ~r/navigated away before the action reached it/, fn ->
      click(session, by_role(:button, name: "Lull guardian", exact: true), timeout: 0)
    end

    session
    |> expect(Fluffy.Expect.page_to_have_url("/live/secret-chamber"))
    |> expect("The secret chamber is open" |> by_text() |> to_be_visible())
  end

  @tag driver: :phoenix
  test "an action without timeout budget acts on the document Live patches changed after the last read" do
    :phoenix
    |> live_session()
    |> visit("/live/chamber-map?async=patch-twice")
    |> await_unread_patches(:phoenix, 2, nil)
    |> click(by_role(:link, name: "Chamber from here", exact: true), timeout: 0)
    |> expect(Fluffy.Expect.page_to_have_url("/chamber?from=late-patched"))
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

  # Waits until the view has pushed `count` patches without Fluffy reading
  # them, so the next action still targets the document Fluffy last saw.
  defp await_unread_patches(session, :phoenix, count, _url) do
    {reference, _topic, _proxy_pid} = Fluffy.Session.page_state(session).view.proxy
    await_patch_messages(reference, count, System.monotonic_time(:millisecond) + 1_000)
    session
  end

  defp await_unread_patches(session, :playwright, _count, url), do: expect(session, Fluffy.Expect.page_to_have_url(url))

  defp await_patch_messages(reference, count, deadline) do
    {:messages, messages} = Process.info(self(), :messages)

    cond do
      Enum.count(messages, &match?({^reference, {:patch, _topic, _options}}, &1)) >= count ->
        :ok

      System.monotonic_time(:millisecond) < deadline ->
        Process.sleep(5)
        await_patch_messages(reference, count, deadline)

      true ->
        flunk("expected #{count} unread Live patches")
    end
  end

  defp live_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
