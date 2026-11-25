defmodule Fluffy.Conformance.PageReadTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  # Playwright's page.content(), page.title(), locator.all() and locator.waitFor().

  # The browser's serialization of /notice-board: its doctype and <html>, without the comments
  # around it, void elements without an end tag and Playwright's escapes.
  @notice_board String.trim_trailing(~S"""
                <!DOCTYPE html><html lang="en"><head>
                    <meta charset="utf-8">
                    <title>
                      Hogwarts   notice board
                    </title>
                  </head>
                  <body>
                    <h1 title="The &quot;official&quot; board" data-houses="Gryffindor &amp; Slytherin">Notices &amp; owls</h1>
                    <p>Fred&nbsp;&amp;&nbsp;George's<br>Wizard Wheezes &lt;opening soon&gt;</p>
                    <img alt="A snowy owl">
                    <form>
                      <input name="owl" value="Errol" aria-label="Owl">
                      <label><input type="checkbox" name="post">Owl post</label>
                      <textarea name="letter" aria-label="Letter">Dear Harry</textarea>
                    </form>
                    <svg viewBox="0 0 10 10"><circle r="1"></circle></svg>
                    <script type="text/plain">if (owls < 3 && post) send("Hedwig")</script>


                </body></html>
                """)

  @shuffle by_role(:button, name: "Shuffle the notices")

  for driver <- Drivers.backends() do
    @tag driver: driver
    test "content and title read a static page as the browser does with #{driver}", %{driver: driver} do
      session = driver |> start_session() |> visit("/notice-board")

      assert content(session) == @notice_board
      assert title(session) == "Hogwarts notice board"

      # What a user types or checks is the control's state, not an attribute.
      session =
        session
        |> fill(by_label("Owl", exact: true), "Hedwig")
        |> fill(by_label("Letter"), "Dear Ron")
        |> check(by_label("Owl post"))

      assert content(session) == @notice_board
    end

    @tag driver: driver
    test "content and title follow a LiveView's renders and live_title with #{driver}", %{driver: driver} do
      session = driver |> start_session() |> visit("/live/notice-board")

      assert title(session) == "Notice board"
      assert content(session) =~ ~r/^<!DOCTYPE html><html lang="en"/
      assert content(session) =~ ~s(<li id="quidditch">Quidditch trials</li>)

      session = session |> click(@shuffle) |> expect(page_to_have_title("Shuffled notice board"))
      html = content(session)

      assert title(session) == "Shuffled notice board"
      assert html =~ ~s(<title data-default="Fluffy's enchanted stage">Shuffled notice board</title>)
      assert html =~ ~s(<li id="toad" hidden="">Lost toad</li>)
      assert html =~ ~s(<li id="hogsmeade">Hogsmeade weekend</li>)
      refute html =~ "Quidditch trials"
    end

    @tag driver: driver
    test "wait_for waits for each state on a LiveView with #{driver}", %{driver: driver} do
      session =
        driver
        |> start_session()
        |> visit("/live/notice-board")
        |> expect(to_be_visible(by_text("Quidditch trials")))
        |> expect(to_be_visible(by_text("Lost toad")))
        |> expect(to_be_hidden(by_text("Detention with Snape")))
        |> expect(not_(to_be_attached(by_text("Hogsmeade weekend"))))
        |> click(@shuffle)

      assert session
             |> wait_for(by_text("Hogsmeade weekend"), state: :attached)
             |> wait_for(by_text("Quidditch trials"), state: :detached)
             |> wait_for(by_text("Detention with Snape"))
             |> wait_for(by_text("Lost toad"), state: :hidden) == session
    end

    @tag driver: driver
    test "wait_for times out on a LiveView with #{driver}", %{driver: driver} do
      session = driver |> start_session() |> visit("/live/notice-board")

      for {locator, state} <- [
            {by_text("Hogsmeade weekend"), :attached},
            {by_text("Detention with Snape"), :visible},
            {by_text("Lost toad"), :hidden},
            {by_text("Quidditch trials"), :detached}
          ] do
        error = assert_raise Fluffy.OperationError, fn -> wait_for(session, locator, state: state, timeout: 200) end
        assert error.operation == :wait_for
        assert error.locator == locator
      end

      # Strict, as an action, whatever the state.
      for options <- [[], [state: :hidden]] do
        error =
          assert_raise Fluffy.OperationError, fn -> wait_for(session, by_role(:listitem), [timeout: 1_000] ++ options) end

        assert strictness_error?(error)
      end
    end

    @tag driver: driver
    test "all lists the current matches of a LiveView with #{driver}", %{driver: driver} do
      session = driver |> start_session() |> visit("/live/notice-board")
      notices = for notice <- all(session, by_role(:listitem)), do: text_content(session, notice)
      assert notices == ["Quidditch trials", "Lost toad"]

      session = session |> click(@shuffle) |> expect(to_be_visible(by_text("Hogsmeade weekend")))
      notices = for notice <- all(session, by_role(:listitem)), do: text_content(session, notice)
      assert notices == ["Detention with Snape", "Hogsmeade weekend"]
    end
  end

  for driver <- Drivers.html() do
    @tag driver: driver
    test "all returns a locator per match, none, one or several, with #{driver}" do
      html = """
      <ul>
        <li><label><input type="checkbox">Hedwig</label></li>
        <li><label><input type="checkbox">Errol</label></li>
        <li><label><input type="checkbox">Pigwidgeon</label></li>
      </ul>
      <p id="post">Owl post</p>
      """

      with_html(unquote(driver), html, fn session ->
        assert all(session, by_css("#howler")) == []
        assert [post] = all(session, by_css("#post"))
        expect(session, to_have_text(post, "Owl post"))

        owls = all(session, by_role(:checkbox))
        assert owls == for(index <- 0..2, do: nth(by_role(:checkbox), index))

        session = Enum.reduce(owls, session, &check(&2, &1))
        for owl <- owls, do: expect(session, to_be_checked(owl))
        assert Enum.map(all(session, by_role(:listitem)), &text_content(session, &1)) == ["Hedwig", "Errol", "Pigwidgeon"]
      end)
    end
  end

  @tag driver: :static
  test "wait_for checks once on a Static page" do
    html = ~s(<p>Hagrid's hut</p><p id="forest" hidden>Forbidden forest</p>)

    with_html(:static, html, fn session ->
      assert session
             |> wait_for(by_text("Hagrid's hut"))
             |> wait_for(by_css("#forest"), state: :attached)
             |> wait_for(by_css("#forest"), state: :hidden)
             |> wait_for(by_css("#lake"), state: :detached)
             |> wait_for(by_css("#lake"), state: :hidden) == session

      # Nothing changes on a Static page, so it fails at once, whatever the timeout.
      started = System.monotonic_time(:millisecond)

      for {locator, state} <- [
            {by_css("#lake"), :attached},
            {by_css("#forest"), :visible},
            {by_css("#forest"), :detached}
          ] do
        error = assert_raise Fluffy.OperationError, fn -> wait_for(session, locator, state: state, timeout: 5_000) end
        assert error.operation == :wait_for
      end

      assert System.monotonic_time(:millisecond) - started < 1_000
    end)
  end

  @tag driver: :static
  test "content takes no Playwright option on Phoenix" do
    with_html(:static, "<p>Lumos</p>", fn session ->
      error = assert_raise Fluffy.CapabilityError, fn -> content(session, include_shadow: true) end
      assert error.capability == :playwright_action_options
    end)
  end

  defp strictness_error?(%{backend: :phoenix, cause: cause}),
    do: match?(%Fluffy.StrictnessError{candidates: [_, _ | _]}, cause)

  defp strictness_error?(%{backend: :playwright} = error), do: Exception.message(error) =~ "strict mode violation"
end
