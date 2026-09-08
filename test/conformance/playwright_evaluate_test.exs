defmodule Fluffy.Conformance.PlaywrightEvaluateTest do
  use Fluffy.TestCase, async: true

  import Fluffy

  alias Fluffy.CapabilityError
  alias Fluffy.Playwright

  test "evaluates JavaScript in the active Playwright page and returns the value" do
    session =
      session_for_html(:playwright, "<main><h1>Hello</h1><p data-state=ready>Ready</p></main>",
        base_url: Fluffy.TestServer.base_url()
      )

    assert "Hello" ==
             Playwright.evaluate(session, "document.querySelector('h1').textContent")

    assert %{"count" => 1, "state" => "ready"} ==
             Playwright.evaluate(session, """
             ({
               count: document.querySelectorAll('h1').length,
               state: document.querySelector('[data-state]').dataset.state
             })
             """)
  end

  test "supports function-style evaluation with an argument and a custom timeout" do
    session =
      session_for_html(:playwright, "<main><p id=status>Ready</p></main>", base_url: Fluffy.TestServer.base_url())

    assert "Ready!" ==
             Playwright.evaluate(
               session,
               "suffix => document.querySelector('#status').textContent + suffix",
               is_function: true,
               arg: "!",
               timeout: 1_000
             )
  end

  test "raises a capability error outside the Playwright driver" do
    session =
      :phoenix
      |> start_session(
        endpoint: Fluffy.TestWeb.Endpoint,
        base_url: Fluffy.TestServer.base_url()
      )
      |> visit("/chamber")

    assert_raise CapabilityError, ~r/:static does not support :javascript_evaluation/, fn ->
      Playwright.evaluate(session, "document.title")
    end
  end

  test "raises on Playwright evaluation failure" do
    session =
      session_for_html(:playwright, "<main>Failure</main>", base_url: Fluffy.TestServer.base_url())

    assert_raise RuntimeError, ~r/Playwright evaluate failed/, fn ->
      Playwright.evaluate(session, "(() => { throw new Error('boom') })()")
    end
  end
end
