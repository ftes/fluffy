defmodule Fluffy.Conformance.AssertAPITest do
  use Fluffy.TestCase, async: true
  use Fluffy.Assert

  import Fluffy
  import Fluffy.Locator

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "assert and refute preserve locator and page semantics with #{driver}" do
      session =
        session_for_html(
          unquote(driver),
          """
          <p id="visible">Saved</p>
          <p id="hidden" hidden>Hidden</p>
          <input aria-label="Subscribe" type="checkbox" checked>
          """,
          base_url: Fluffy.TestServer.base_url()
        )

      expectation = visible(by_css("#visible"))

      returned =
        session
        |> assert(expectation)
        |> assert(checked(by_label("Subscribe")))
        |> refute(visible(by_css("#hidden")))
        |> refute(visible(by_css("#absent")))
        |> assert(count(by_css("#hidden"), 1))
        |> refute(count(by_css("#visible"), 2))
        |> refute(page_title("Error"), timeout: 20)

      assert returned == session

      assert_raise ExUnit.AssertionError, fn ->
        refute(session, expectation, timeout: 20)
      end

      assert_raise ExUnit.AssertionError, fn ->
        refute(session, count(by_css("#visible"), 1), timeout: 20)
      end
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "assertions retry Live changes and return a usable session with #{driver}" do
      unquote(driver)
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Fluffy.TestWeb.Endpoint)
      |> visit("/live/async?delay=40")
      |> refute(visible(by_text("Status: waiting")), timeout: 1_000)
      |> assert(visible(by_text("Status: ready")), timeout: 1_000)
      |> assert(page_url(path: "/live/async"))
      |> click(by_role(:button, name: "Appeared"))
      |> assert(visible(by_text("Activated")))
    end
  end

  test "refute preserves unsupported-operation errors" do
    session = session_for_html(:static, ~s(<input type="checkbox" aria-label="Subscribe">))

    assert_raise Fluffy.CapabilityError, fn ->
      refute(session, checked(by_label("Subscribe"), indeterminate: true))
    end
  end

  test "captured results use flat constructors and negation" do
    session = session_for_html(:static, "<p>Saved</p>")

    session = %{
      session
      | results: %{
          receipt: %{type: :download, value: %{filename: "receipt.pdf", bytes: "pdf"}},
          confirmation: %{type: :dialog, value: %{message: "Saved"}},
          destination: %{type: :navigation, value: %{url: "https://example.test/receipt"}},
          payment: %{type: :request, value: %{method: "POST"}},
          result: %{type: :response, value: %{status: 201}}
        }
    }

    session
    |> assert(download_suggested_filename(:receipt, "receipt.pdf"))
    |> assert(download_size(:receipt, 3))
    |> assert(dialog_message(:confirmation, "Saved"))
    |> assert(navigation_url(:destination, path: "/receipt"))
    |> assert(request_method(:payment, "POST"))
    |> assert(response_status(:result, 201))
    |> refute(response_status(:result, 500))

    assert_raise ExUnit.AssertionError, fn ->
      refute(session, response_status(:result, 201))
    end
  end
end
