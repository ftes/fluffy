defmodule Fluffy.Conformance.AssertAPITest do
  use Fluffy.Support.Case, async: true
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

  test "every Fluffy.Expect matcher has a Fluffy.Assert name" do
    assert_names = Fluffy.Assert.__info__(:functions)

    missing =
      for {name, arity} <- Fluffy.Expect.__info__(:functions),
          name not in [:__struct__, :expect, :expect_event, :not_],
          assert_name = name |> Atom.to_string() |> assert_name() |> String.to_atom(),
          {assert_name, arity} not in assert_names,
          do: {name, arity}

    assert missing == []
  end

  # `to_be_visible` is `visible`, `to_contain_text` is `contain_text` and
  # `page_to_have_title` is `page_title`. Baseline comparisons keep `match_`, like
  # `match_aria_snapshot`: `to_have_screenshot` is `match_screenshot`.
  defp assert_name("page_" <> matcher), do: "page_" <> assert_name(matcher)
  defp assert_name("to_have_screenshot"), do: "match_screenshot"
  defp assert_name("to_be_" <> name), do: name
  defp assert_name("to_have_" <> name), do: name
  defp assert_name("to_" <> name), do: name

  for driver <- Drivers.html() do
    @tag driver: driver
    test "role and accessible name and description delegate to their expectations with #{driver}" do
      html = ~s(<label>Name <input aria-describedby="hint"></label><p id="hint">Your full name</p>)

      with_html(unquote(driver), html, fn session ->
        field = by_label("Name")

        session
        |> assert(role(field, :textbox))
        |> refute(role(field, :button))
        |> assert(accessible_name(field, "Name"))
        |> assert(accessible_name(field, "name", ignore_case: true))
        |> refute(accessible_name(field, "Other"))
        |> assert(accessible_description(field, ~r/full name/))
        |> refute(accessible_description(field, "Other"))
      end)
    end
  end

  @tag driver: :playwright
  test "browser-only element and page assertions delegate to their expectations" do
    html = """
    <p id="note" style="color: rgb(255, 0, 0)">Saved</p>
    <label>Name <input value="Hedwig" aria-invalid="true" aria-errormessage="problem"></label>
    <p id="problem">Too short</p>
    """

    note = by_css("#note")
    field = by_label("Name")

    :playwright
    |> session_for_html(html)
    |> assert(css(note, "color", "rgb(255, 0, 0)"))
    |> assert(css(note, "color", ~r/^rgb\(255/))
    |> refute(css(note, "color", "rgb(0, 0, 0)"))
    |> assert(js_property(field, "value", "Hedwig"))
    |> refute(js_property(field, "value", "Errol"))
    |> assert(accessible_error_message(field, "Too short"))
    |> refute(accessible_error_message(field, "Other"))
    |> assert(match_aria_snapshot(note, "- paragraph: Saved"))
    |> refute(match_aria_snapshot(note, "- paragraph: Lost"))
    |> assert(page_match_aria_snapshot("- paragraph: Too short"))
    |> refute(page_match_aria_snapshot("- heading \"Lost\""))
  end

  @tag driver: :playwright
  @tag :tmp_dir
  test "match_screenshot and page_match_screenshot delegate to their expectations", %{tmp_dir: tmp_dir} do
    box = by_css("#box")
    path = Path.join(tmp_dir, "box.png")
    page_path = Path.join(tmp_dir, "page.png")
    session = session_for_html(:playwright, ~s(<div id="box" style="width: 60px; height: 40px; background: green"></div>))

    # The first run writes the baselines.
    ExUnit.CaptureIO.capture_io(fn ->
      session
      |> assert(match_screenshot(box, path: path))
      |> assert(page_match_screenshot(path: page_path))
    end)

    session
    |> assert(match_screenshot(box, path: path))
    |> assert(page_match_screenshot(path: page_path))

    Fluffy.Playwright.evaluate(session, "document.querySelector('#box').style.background = 'red'")

    session
    |> refute(match_screenshot(box, path: path), timeout: 2_000)
    |> refute(page_match_screenshot(path: page_path), timeout: 2_000)
  end

  for driver <- Drivers.phoenix() do
    @tag driver: driver
    test "browser-only assertions raise a capability error, also refuted, with #{driver}" do
      session =
        case unquote(driver) do
          :static -> session_for_html(:static, "<p>Top</p>")
          :live -> :phoenix |> start_session() |> visit("/live/potions")
        end

      p = by_css("p")

      for expectation <- [
            css(p, "color", "red"),
            js_property(p, "value", "x"),
            match_screenshot(p, path: "x.png"),
            page_match_screenshot(path: "x.png"),
            accessible_error_message(p, "x"),
            match_aria_snapshot(p, "- paragraph"),
            page_match_aria_snapshot("- paragraph")
          ],
          run <- [&Fluffy.Assert.assert/2, &Fluffy.Assert.refute/2] do
        error = assert_raise Fluffy.CapabilityError, fn -> run.(session, expectation) end
        assert error.driver == unquote(driver)
        assert Fluffy.Capability.status(error.capability, unquote(driver)) == :browser_only
      end
    end
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

  for driver <- Drivers.html() do
    @tag driver: driver
    test "assert and refute preserve locator and page semantics with #{driver}" do
      session =
        session_for_html(
          unquote(driver),
          """
          <p id="visible">Saved</p>
          <p id="hidden" hidden>Hidden</p>
          <input aria-label="Join the Quidditch team" type="checkbox" checked>
          """
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
    |> session_for_html("<p>Saved</p>")
    |> assert(visible(by_text("Saved")), timeout: 0)
    |> refute(page_title("Error"), timeout: 0)
    |> assert(visible(by_text("Saved")))
  end

  for driver <- Drivers.backends() do
    @tag driver: driver
    test "assertions retry Live changes and return a usable session with #{driver}" do
      unquote(driver)
      |> start_session()
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
