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

  defp live_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
