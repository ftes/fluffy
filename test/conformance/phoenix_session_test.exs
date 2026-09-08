defmodule Fluffy.Conformance.PhoenixSessionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Session

  test "one Phoenix session classifies page drivers without losing history" do
    session = start_session(:phoenix)

    assert Session.current_driver(session) == :unvisited

    session = visit(session, "/chamber")
    assert Session.current_driver(session) == :static
    expect(session, visible(by_text("The guardian sleeps")))

    session = visit(session, "/live/three-heads")
    assert Session.current_driver(session) == :live
    expect(session, visible(by_text("Sleeping heads: 0")))

    session = click(session, by_role(:button, name: "Play the flute"))
    assert Session.current_driver(session) == :live
    assert Session.current_page(session).revision == 2
    expect(session, visible(by_text("Sleeping heads: 1")))

    session = visit(session, "/chamber")
    assert Session.current_driver(session) == :static

    assert Session.current_page(session).revision == 3
  end
end
