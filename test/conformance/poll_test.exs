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
