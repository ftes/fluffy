defmodule Fluffy.Conformance.TimeoutInfinityTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  # `Fluffy.Conformance.DefaultTimeoutTest` waits past the default with `:infinity`.
  @tag driver: :static
  test "timeout: :infinity checks once with static" do
    session =
      :static
      |> session_for_html(~s|<main><p>Here</p><label>Name <input name="name"></label></main>|)
      |> expect("Here" |> by_text() |> to_be_visible(), timeout: :infinity)
      |> fill(by_label("Name"), "Hermione", timeout: :infinity)
      |> expect(to_have_value(by_label("Name"), "Hermione", timeout: :infinity))

    assert_raise ExUnit.AssertionError, fn ->
      expect(session, "Missing" |> by_text() |> to_be_visible(), timeout: :infinity)
    end
  end

  # `0` checks once in Elixir but means no limit in Playwright, so it raises on every entry.
  test "timeout: rejects 0, naming :once and :infinity, and other atoms" do
    session = session_for_html(:static, ~s|<button>Go</button>|)
    button = by_role(:button, name: "Go")

    for {value, message} <- [
          {0, ~r/timeout option: 0 is ambiguous: pass :once to check once or :infinity for no limit/},
          {:forever, ~r/timeout option: expected a positive integer, :once or :infinity, got: :forever/}
        ],
        operation <- [
          fn -> click(session, button, timeout: value) end,
          fn -> expect(session, to_be_visible(button, timeout: value)) end,
          fn -> expect(session, to_be_visible(button), timeout: value) end,
          fn -> expect(session, to_pass(fn _session -> :ok end, timeout: value)) end,
          fn -> expect(session, poll(fn _session -> 1 end, &assert(&1 == 1), timeout: value)) end,
          fn -> wait_for(session, Fluffy.Event.download(), timeout: value) end
        ] do
      assert_raise NimbleOptions.ValidationError, message, operation
    end
  end

  @tag driver: :playwright
  test "timeout: rejects 0 on a Playwright action" do
    session = session_for_html(:playwright, ~s|<button>Go</button>|)

    assert_raise NimbleOptions.ValidationError, ~r/0 is ambiguous/, fn ->
      Fluffy.Playwright.hover(session, by_role(:button), timeout: 0)
    end
  end
end
