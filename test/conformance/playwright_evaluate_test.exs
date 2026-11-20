defmodule Fluffy.Conformance.PlaywrightEvaluateTest do
  use Fluffy.Support.Case, async: true

  import Fluffy

  alias Fluffy.CapabilityError

  test "evaluates JavaScript in the active Playwright page and returns the value" do
    session =
      session_for_html(:playwright, "<main><h1>Lumos</h1><p data-state=ready>Ready</p></main>")

    assert "Lumos" ==
             Fluffy.Playwright.evaluate(session, "document.querySelector('h1').textContent")

    assert %{"count" => 1, "state" => "ready"} ==
             Fluffy.Playwright.evaluate(session, """
             ({
               count: document.querySelectorAll('h1').length,
               state: document.querySelector('[data-state]').dataset.state
             })
             """)
  end

  test "supports function-style evaluation with an argument" do
    session =
      session_for_html(:playwright, "<main><p id=status>Ready</p></main>")

    assert "Ready!" ==
             Fluffy.Playwright.evaluate(
               session,
               "suffix => document.querySelector('#status').textContent + suffix",
               "!"
             )
  end

  # As in Playwright, page evaluation has no timeout.
  test "rejects timeout: in place of the argument" do
    session = session_for_html(:playwright, "<main>Options</main>")

    assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:timeout/, fn ->
      Fluffy.Playwright.evaluate(session, "1 + 1", timeout: 1_000)
    end
  end

  test "raises a capability error outside the Playwright driver" do
    session =
      :phoenix
      |> start_session()
      |> visit("/chamber")

    assert_raise CapabilityError, ~r/Phoenix \(:static\) does not support :evaluate \(:javascript_evaluation\)/, fn ->
      Fluffy.Playwright.evaluate(session, "document.title")
    end
  end

  test "raises on Playwright evaluation failure" do
    session =
      session_for_html(:playwright, "<main>Failure</main>")

    assert_raise Playwright.PlaywrightError, ~r/boom/, fn ->
      Fluffy.Playwright.evaluate(session, "(() => { throw new Error('boom') })()")
    end
  end
end
