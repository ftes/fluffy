defmodule Fluffy.Conformance.PollTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Support.Repo

  # Each test changes the page or app state from its callback's second attempt, so the first
  # attempt fails whatever the machine's speed, and a later one passes.

  describe "a LiveView page that changes between attempts" do
    for driver <- [:live, :playwright] do
      @tag driver: driver
      test "poll! retries a value read from the session with #{driver}", %{driver: driver} do
        {session, attempt} = visit_owlery(driver)

        Playwright.Expect.poll!(
          fn ->
            attempt.()
            letters(session, driver)
          end,
          &assert(&1 == 1)
        )

        assert attempt.() > 2
      end

      @tag driver: driver
      test "to_pass! retries Fluffy actions and expectations with #{driver}", %{driver: driver} do
        {session, attempt} = visit_owlery(driver)

        session =
          Playwright.Expect.to_pass!(fn ->
            attempt.()

            session
            |> click(by_role(:button, name: "Read the letter"), timeout: 100)
            |> expect(to_be_visible(by_text("You have been accepted at Hogwarts")), timeout: 0)
          end)

        assert %Fluffy.Session{} = session
        assert attempt.() > 2
        expect(session, to_have_text(by_css("#letters"), "Letters: 1"))
      end

      @tag driver: driver
      test "the tuple forms return the result with #{driver}", %{driver: driver} do
        {session, attempt} = visit_owlery(driver)

        assert :ok =
                 Playwright.Expect.poll(
                   fn ->
                     attempt.()
                     letters(session, driver)
                   end,
                   &assert(&1 == 1)
                 )

        assert {:ok, 1} = Playwright.Expect.to_pass(fn -> 1 = letters(session, driver) end)
      end

      @tag driver: driver
      test "poll! fails with the last value it received with #{driver}", %{driver: driver} do
        {session, _attempt} = visit_owlery(driver)

        error =
          assert_raise Playwright.ExpectError, fn ->
            Playwright.Expect.poll!(fn -> letters(session, driver) end, &assert(&1 == 1),
              message: "an owl from Hogwarts",
              timeout: 300
            )
          end

        assert error.message =~ "an owl from Hogwarts"
        assert error.message =~ "left:  0"
        assert error.message =~ "Timeout 300ms exceeded while waiting on the predicate"
      end

      @tag driver: driver
      test "an expect inside to_pass! waits its own timeout on each attempt with #{driver}", %{driver: driver} do
        {session, attempt} = visit_owlery(driver)
        started = System.monotonic_time(:millisecond)

        error =
          assert_raise Playwright.ExpectError, fn ->
            Playwright.Expect.to_pass!(
              fn ->
                attempt.()
                expect(session, to_be_visible(by_text("A howler")), timeout: 600)
              end,
              timeout: 200
            )
          end

        # The one attempt outlasts to_pass!'s timeout: it is not interrupted, and no other starts.
        assert System.monotonic_time(:millisecond) - started >= 600
        assert attempt.() == 2
        assert error.message =~ "A howler"
        assert error.message =~ "Timeout 200ms exceeded while waiting on the predicate"
      end
    end
  end

  describe "to_pass and poll in a pipeline on a LiveView page" do
    for driver <- [:live, :playwright] do
      @tag driver: driver
      test "to_pass retries a block and returns a usable session with #{driver}", %{driver: driver} do
        {session, attempt} = visit_owlery(driver)

        session
        |> expect(
          to_pass(fn session ->
            attempt.()

            session
            |> click(by_role(:button, name: "Read the letter"), timeout: 100)
            |> expect(to_be_visible(by_text("You have been accepted at Hogwarts")), timeout: 0)
          end)
        )
        |> expect(to_have_text(by_css("#letters"), "Letters: 1"))

        assert attempt.() > 2
      end

      @tag driver: driver
      test "poll retries a value read through the session with #{driver}", %{driver: driver} do
        {session, attempt} = visit_owlery(driver)

        returned =
          expect(
            session,
            poll(
              fn session ->
                attempt.()
                text_content(session, by_css("#letters"))
              end,
              &assert(&1 == "Letters: 1")
            )
          )

        assert returned == session
        assert attempt.() > 2
      end

      @tag driver: driver
      test "a failing to_pass raises its last attempt's error with #{driver}", %{driver: driver} do
        {session, _attempt} = visit_owlery(driver)
        block = fn session -> expect(session, to_be_visible(by_text("A howler")), timeout: 0) end

        error = assert_raise ExUnit.AssertionError, fn -> expect(session, to_pass(block), timeout: 300) end

        assert error.message =~ ~r/\AExpected the block to pass\n/
        assert error.message =~ "A howler"
        assert error.message =~ "Timeout 300ms exceeded while waiting on the predicate"
      end

      @tag driver: driver
      test "a failing poll raises with its message and the last value with #{driver}", %{driver: driver} do
        {session, _attempt} = visit_owlery(driver)

        error =
          assert_raise ExUnit.AssertionError, fn ->
            expect(
              session,
              poll(&text_content(&1, by_css("#letters")), &assert(&1 == "Letters: 1"),
                message: "an owl from Hogwarts",
                timeout: 300
              )
            )
          end

        assert error.message =~ ~r/\AExpected the polled value to pass the assertion\n/
        assert error.message =~ "an owl from Hogwarts"
        assert error.message =~ ~s(left:  "Letters: 0")
        assert error.message =~ "Timeout 300ms exceeded while waiting on the predicate"
      end
    end

    @tag driver: :playwright
    test "poll retries a value the browser evaluates" do
      {session, attempt} = visit_owlery(:playwright)

      expect(
        session,
        poll(
          fn session ->
            attempt.()
            Fluffy.Playwright.evaluate(session, "document.querySelector('#letters').textContent")
          end,
          &assert(&1 == "Letters: 1")
        )
      )

      assert attempt.() > 2
    end
  end

  describe "to_pass and poll on every driver" do
    for driver <- Drivers.all() do
      @tag driver: driver
      test "a negated to_pass retries until the block raises with #{driver}", %{driver: driver} do
        session = owlery_or_html(driver)
        attempt = on_attempt(0, fn -> :ok end)
        block = fn _session -> if attempt.() > 1, do: flunk("Hedwig flew off") end

        assert expect(session, not_(to_pass(block)), timeout: 5_000) == session
        assert attempt.() > 2
      end

      @tag driver: driver
      test "a negated to_pass fails at the timeout while the block passes with #{driver}", %{driver: driver} do
        session = owlery_or_html(driver)

        error = assert_raise ExUnit.AssertionError, fn -> expect(session, not_(to_pass(& &1)), timeout: 300) end

        assert error.message =~ ~r/\AExpected not the block to pass\n/
        assert error.message =~ "Timeout 300ms exceeded while waiting on the predicate"
      end

      @tag driver: driver
      test "a negated to_pass with a timeout of 0 makes one attempt with #{driver}", %{driver: driver} do
        session = owlery_or_html(driver)
        attempt = on_attempt(0, fn -> :ok end)

        assert expect(session, not_(to_pass(fn _session -> flunk("Hedwig flew off #{attempt.()}") end)), timeout: 0) ==
                 session

        assert attempt.() == 2

        error =
          assert_raise ExUnit.AssertionError, fn ->
            expect(session, not_(to_pass(fn _session -> attempt.() end)), timeout: 0)
          end

        assert error.message == "Expected not the block to pass\nThe block passed"
        assert attempt.() == 4
      end

      @tag driver: driver
      test "the execution call's options win over the constructor's with #{driver}", %{driver: driver} do
        session = owlery_or_html(driver)

        for build <- [
              &to_pass(fn _session -> flunk("No owl yet #{&1.()}") end, intervals: [1_000], timeout: 10_000),
              &poll(fn _session -> &1.() end, fn _ -> flunk("No owl yet") end, intervals: [1_000], timeout: 10_000)
            ] do
          attempt = on_attempt(0, fn -> :ok end)
          error = assert_raise ExUnit.AssertionError, fn -> expect(session, build.(attempt), timeout: 300) end

          assert error.message =~ "No owl yet"
          assert error.message =~ "Timeout 300ms exceeded while waiting on the predicate"
          # One attempt: the constructor's interval outlasts the execution call's timeout. The
          # default intervals would make several.
          assert attempt.() == 2
        end
      end

      @tag driver: driver
      test "a timeout of 0 makes one attempt with #{driver}", %{driver: driver} do
        session = owlery_or_html(driver)

        for build <- [
              &to_pass(fn _session -> flunk("No owl yet #{&1.()}") end),
              &poll(fn _session -> &1.() end, fn _ -> flunk("No owl yet") end)
            ] do
          attempt = on_attempt(0, fn -> :ok end)
          error = assert_raise ExUnit.AssertionError, fn -> expect(session, build.(attempt), timeout: 0) end

          assert error.message =~ "No owl yet"
          # No retry loop: Playwright's at 1ms can time out before its first attempt.
          refute error.message =~ "Timeout"
          assert attempt.() == 2
        end

        poll = poll(fn _session -> 0 end, &assert(&1 == 1), message: "an owl from Hogwarts")
        error = assert_raise ExUnit.AssertionError, fn -> expect(session, poll, timeout: 0) end
        assert error.message =~ ~r/\AExpected the polled value to pass the assertion\nan owl from Hogwarts\n\n.*left:  0/s

        for block <- [fn _session -> throw(:hedwig) end, fn _session -> exit(:hedwig) end] do
          error = assert_raise ExUnit.AssertionError, fn -> expect(session, to_pass(block), timeout: 0) end
          assert error.message =~ ~r/\AExpected the block to pass\n\*\* \((throw|exit)\) :hedwig/
        end
      end

      @tag driver: driver
      test "a block's other value and any timeout return the given session with #{driver}", %{driver: driver} do
        session = owlery_or_html(driver)
        assert expect(session, to_pass(fn _session -> :hedwig end)) == session

        for timeout <- [0, :infinity] do
          assert expect(session, to_pass(fn _session -> :hedwig end), timeout: timeout) == session
          assert expect(session, poll(fn _session -> 1 end, &assert(&1 == 1)), timeout: timeout) == session
        end
      end

      @tag driver: driver
      test "a raising poll callback fails at once with #{driver}", %{driver: driver} do
        session = owlery_or_html(driver)
        attempt = on_attempt(0, fn -> :ok end)

        assert_raise RuntimeError, "Errol crashed", fn ->
          expect(
            session,
            poll(
              fn _session ->
                attempt.()
                raise "Errol crashed"
              end,
              &assert(&1)
            )
          )
        end

        assert attempt.() == 2
      end
    end

    test "poll can't be negated" do
      assert_raise ArgumentError, ~r/poll\/3 can't be negated.*refute in the assertion instead/, fn ->
        not_(poll(& &1, &assert(&1)))
      end
    end
  end

  describe "a Static page, which doesn't change between attempts" do
    setup {Fluffy.Support.Case, :start_sandbox}

    setup do
      Repo.query!("CREATE TEMP TABLE fluffy_records (value text NOT NULL) ON COMMIT DROP")
      :ok
    end

    @tag driver: :static
    test "poll! retries app state while the page stays as it was" do
      session = :phoenix |> start_session() |> visit("/database")
      deliver = on_attempt(2, fn -> Repo.query!("INSERT INTO fluffy_records (value) VALUES ('Hedwig')") end)

      Playwright.Expect.poll!(
        fn ->
          deliver.()
          Repo.query!("SELECT value FROM fluffy_records").rows
        end,
        &assert(&1 == [["Hedwig"]])
      )

      assert {:error, %Playwright.ExpectError{}} =
               Playwright.Expect.to_pass(
                 fn -> expect(session, to_be_visible(by_text("Static values: Hedwig")), timeout: 0) end,
                 timeout: 300
               )

      session |> reload() |> expect(to_be_visible(by_text("Static values: Hedwig")), timeout: 0)
    end

    @tag driver: :static
    test "to_pass! sees app state after a reload" do
      session = :phoenix |> start_session() |> visit("/database")
      deliver = on_attempt(2, fn -> Repo.query!("INSERT INTO fluffy_records (value) VALUES ('Errol')") end)

      Playwright.Expect.to_pass!(fn ->
        deliver.()

        session
        |> reload()
        |> expect(to_be_visible(by_text("Static values: Errol")), timeout: 0)
      end)
    end

    @tag driver: :static
    test "poll retries app state and to_pass a reload in a pipeline" do
      session = :phoenix |> start_session() |> visit("/database")
      deliver = on_attempt(2, fn -> Repo.query!("INSERT INTO fluffy_records (value) VALUES ('Hedwig')") end)

      session
      |> expect(
        poll(
          fn _session ->
            deliver.()
            Repo.query!("SELECT value FROM fluffy_records").rows
          end,
          &assert(&1 == [["Hedwig"]])
        )
      )
      |> expect(not_(to_be_visible(by_text("Static values: Hedwig"))), timeout: 0)

      deliver = on_attempt(2, fn -> Repo.query!("UPDATE fluffy_records SET value = 'Errol'") end)

      session
      |> expect(
        to_pass(fn session ->
          deliver.()

          session
          |> reload()
          |> expect(to_be_visible(by_text("Static values: Errol")), timeout: 0)
        end)
      )
      |> expect(to_be_visible(by_text("Static values: Errol")), timeout: 0)
    end
  end

  defp owlery_or_html(:static), do: session_for_html(:static, "<p>Owlery</p>")

  defp owlery_or_html(driver) do
    {session, _attempt} = visit_owlery(driver)
    session
  end

  # Visits the owlery; the returned function counts its calls and sends an owl on the second.
  defp visit_owlery(driver) do
    topic = "owlery-#{System.unique_integer([:positive])}"
    session = driver |> backend() |> start_session() |> visit("/live/owlery?topic=#{topic}")
    attempt = on_attempt(2, fn -> Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, :owl) end)
    {session, attempt}
  end

  defp backend(:live), do: :phoenix
  defp backend(:playwright), do: :playwright

  # A function that counts its calls, runs `fun` on call `n`, and returns the call's number.
  defp on_attempt(n, fun) do
    calls = :counters.new(1, [])

    fn ->
      :counters.add(calls, 1, 1)
      call = :counters.get(calls, 1)
      if call == n, do: fun.()
      call
    end
  end

  defp letters(session, :live) do
    session
    |> unwrap_and_return(&(&1 |> Phoenix.LiveViewTest.element("#letters") |> Phoenix.LiveViewTest.render()))
    |> parse_letters()
  end

  defp letters(session, :playwright) do
    session
    |> Fluffy.Playwright.evaluate(by_css("#letters"), "el => el.textContent")
    |> parse_letters()
  end

  defp parse_letters(text) do
    [count] = Regex.run(~r/Letters: (\d+)/, text, capture: :all_but_first)
    String.to_integer(count)
  end
end
