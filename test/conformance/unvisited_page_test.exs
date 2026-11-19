defmodule Fluffy.Conformance.UnvisitedPageTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  @owl by_role(:button, name: "Send the owl")

  # Playwright starts at about:blank, where an action waits for its element.
  @tag driver: :playwright
  test "a Playwright session starts at about:blank" do
    session = start_session(:playwright)

    expect(session, page_to_have_url("about:blank"))

    error = assert_raise Fluffy.OperationError, fn -> click(session, @owl, timeout: 100) end
    assert error.operation == :click
  end

  # Phoenix has no page before the first visit, so everything but a visit raises at once.
  test "a Phoenix session has no page before its first visit" do
    session = start_session(:phoenix)

    for operation <- [
          fn -> click(session, @owl) end,
          fn -> fill(session, by_label("Letter"), "Hogwarts") end,
          fn -> press(session, @owl, "Enter") end,
          fn -> expect(session, to_be_visible(@owl)) end,
          fn -> expect(session, page_to_have_url("/")) end,
          fn -> reload(session) end,
          fn -> unwrap(session, fn _native -> flunk("callback ran") end) end,
          fn -> unwrap_and_return(session, fn _native -> flunk("callback ran") end) end,
          fn -> open_browser(session, fn _path -> flunk("snapshot opened") end) end
        ] do
      assert_raise ArgumentError, ~r/before the first visit/, operation
    end

    session
    |> visit("/chamber")
    |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
  end
end
