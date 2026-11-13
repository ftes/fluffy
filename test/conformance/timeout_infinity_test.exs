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

  test "timeout: rejects other atoms" do
    session = session_for_html(:static, ~s|<button>Go</button>|)

    for operation <- [
          fn -> click(session, by_role(:button, name: "Go"), timeout: :forever) end,
          fn -> expect(session, :button |> by_role() |> to_be_visible(timeout: :forever)) end,
          fn -> expect(session, to_be_visible(by_role(:button)), timeout: :forever) end
        ] do
      assert_raise NimbleOptions.ValidationError, ~r/timeout/, operation
    end
  end
end
