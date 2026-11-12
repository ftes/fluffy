defmodule Fluffy.Conformance.AssertAPITest do
  use Fluffy.TestCase, async: true
  use Fluffy.Assert

  import Fluffy
  import Fluffy.Locator

  test "element assertions delegate to their expectations, without clashing with Fluffy or Fluffy.Locator" do
    session =
      session_for_html(:static, ~s(<p id="note" class="row wide" title="Hint">Saved</p><p id="gone" hidden></p>))

    note = by_css("#note")

    session
    |> assert(text(note, "Saved"))
    |> assert(contain_text(note, "Sav"))
    |> assert(attribute(note, "title"))
    |> assert(attribute(note, "title", "Hint"))
    |> assert(class(note, "row wide"))
    |> assert(contain_class(note, "wide"))
    |> assert(id(note, "note"))
    |> assert(attached(note))
    |> assert(hidden(by_css("#gone")))
    |> assert(empty(by_css("#gone")))
    |> refute(text(note, "Lost"))
    |> refute(empty(note))
  end

  @tag driver: :playwright
  test "in_viewport delegates to to_be_in_viewport, with ratio" do
    session =
      session_for_html(
        :playwright,
        ~s(<div id="top" style="height: 10px">Top</div><div id="far" style="margin-top: 5000px">Far</div>)
      )

    session
    |> assert(in_viewport(by_css("#top")))
    |> assert(in_viewport(by_css("#top"), ratio: 0.5))
    |> refute(in_viewport(by_css("#far")))
  end

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "assert and refute preserve locator and page semantics with #{driver}" do
      session =
        session_for_html(
          unquote(driver),
          """
          <p id="visible">Saved</p>
          <p id="hidden" hidden>Hidden</p>
          <input aria-label="Join the Quidditch team" type="checkbox" checked>
          """,
          base_url: Fluffy.TestServer.base_url()
        )

      expectation = visible(by_css("#visible"))

      returned =
        session
        |> assert(expectation)
        |> assert_has(by_css("#visible"))
        |> refute_has(by_css("#hidden"))
        |> refute_has(by_css("#absent"), timeout: 20)
        |> assert(checked(by_label("Join the Quidditch team")))
        |> refute(visible(by_css("#hidden")))
        |> refute(visible(by_css("#absent")))
        |> assert(count(by_css("#hidden"), 1))
        |> refute(count(by_css("#visible"), 2))
        |> refute(page_title("Error"))

      assert returned == session

      assert_raise ExUnit.AssertionError, fn ->
        assert_has(session, by_css("#hidden"), timeout: 20)
      end

      assert_raise ExUnit.AssertionError, fn ->
        refute_has(session, by_css("#visible"), timeout: 20)
      end

      assert_raise ExUnit.AssertionError, fn ->
        refute(session, expectation, timeout: 20)
      end

      assert_raise ExUnit.AssertionError, fn ->
        refute(session, count(by_css("#visible"), 1), timeout: 20)
      end
    end
  end

  @tag driver: :playwright
  test "immediate browser assertions return a usable session" do
    :playwright
    |> session_for_html("<p>Saved</p>", base_url: Fluffy.TestServer.base_url())
    |> assert(visible(by_text("Saved")), timeout: 0)
    |> refute(page_title("Error"), timeout: 0)
    |> assert(visible(by_text("Saved")))
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "assertions retry Live changes and return a usable session with #{driver}" do
      unquote(driver)
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Fluffy.TestWeb.Endpoint)
      |> visit("/live/async?delay=40")
      |> refute_has(by_text("Status: waiting"), timeout: 1_000)
      |> assert_has(by_text("Status: ready"), timeout: 1_000)
      |> assert(page_url("/live/async?delay=40"))
      |> click(by_role(:button, name: "Appeared"))
      |> assert(visible(by_text("Activated")))
    end
  end

  test "refute preserves unsupported-operation errors" do
    session = session_for_html(:static, ~s(<input type="checkbox" aria-label="Join the Quidditch team">))

    assert_raise Fluffy.CapabilityError, fn ->
      refute(session, checked(by_label("Join the Quidditch team"), indeterminate: true))
    end
  end
end
