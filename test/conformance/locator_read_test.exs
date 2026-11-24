defmodule Fluffy.Conformance.LocatorReadTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  # Playwright's locator reads (textContent, getAttribute, inputValue and allTextContents in
  # locator.ts, frames.ts's callbacks); the cases follow upstream's locator-convenience.spec.ts.
  for driver <- Drivers.html() do
    @tag driver: driver
    test "text_content is the DOM's text content, hidden and script text included with #{driver}" do
      html = """
      <p id="spell">Wingardium <span hidden>secret</span>
        Leviosa<input type="submit" value="Cast"><!-- a note --><script>let feather = 1</script><template>Swish</template></p>
      """

      with_html(unquote(driver), html, fn session ->
        assert text_content(session, by_css("#spell")) == "Wingardium secret\n  Leviosalet feather = 1"
        assert text_content(session, by_css("#spell script")) == "let feather = 1"
        assert text_content(session, by_css("#spell input")) == ""
      end)
    end

    @tag driver: driver
    test "all_text_contents lists every match without waiting with #{driver}" do
      html = "<ul><li>Fluffy</li><li>Norbert <b>the dragon</b></li><li></li></ul>"

      with_html(unquote(driver), html, fn session ->
        assert all_text_contents(session, by_css("li")) == ["Fluffy", "Norbert the dragon", ""]
        assert all_text_contents(session, by_css("li.missing")) == []
      end)
    end

    @tag driver: driver
    test "get_attribute reads the attribute, or nil without it with #{driver}" do
      html = ~s(<a href="/hogwarts" data-house="Gryffindor" download>Hogwarts</a><input aria-label="Owl" value="Errol">)

      with_html(unquote(driver), html, fn session ->
        link = by_role(:link, name: "Hogwarts")
        assert get_attribute(session, link, "href") == "/hogwarts"
        assert get_attribute(session, link, "DATA-HOUSE") == "Gryffindor"
        assert get_attribute(session, link, "download") == ""
        assert get_attribute(session, link, "title") == nil

        # The attribute, not the control's current value.
        session = fill(session, by_label("Owl"), "Hedwig")
        assert get_attribute(session, by_label("Owl"), "value") == "Errol"
      end)
    end

    @tag driver: driver
    test "input_value reads the current value of a control with #{driver}" do
      html = """
      <input aria-label="Owl" value="Errol">
      <textarea aria-label="Letter">Dear Harry</textarea>
      <select aria-label="House"><option>Gryffindor</option><option value="snake">Slytherin</option></select>
      <label id="pet">Pet <input value="Crookshanks"></label>
      <p id="prose">Not a control</p>
      """

      with_html(unquote(driver), html, fn session ->
        assert input_value(session, by_label("Owl")) == "Errol"
        assert input_value(session, by_label("Letter")) == "Dear Harry"
        assert input_value(session, by_label("House")) == "Gryffindor"
        # A label reads its control, as Playwright's follow-label retargeting.
        assert input_value(session, by_css("#pet")) == "Crookshanks"

        session =
          session
          |> fill(by_label("Owl"), "Hedwig")
          |> fill(by_label("Letter"), "Dear Ron")
          |> select_option(by_label("House"), "Slytherin")

        assert input_value(session, by_label("Owl")) == "Hedwig"
        assert input_value(session, by_label("Letter")) == "Dear Ron"
        assert input_value(session, by_label("House")) == "snake"

        error = assert_raise Fluffy.OperationError, fn -> input_value(session, by_css("#prose")) end
        assert error.operation == :input_value
        assert Exception.message(error) =~ "Node is not an <input>, <textarea> or <select> element"
      end)
    end

    @tag driver: driver
    test "a checkbox or radio without a value reads \"on\", checked or not, with #{driver}" do
      html = """
      <label><input type="checkbox">Owl post</label>
      <label><input type="checkbox" checked>Floo powder</label>
      <label><input type="radio" name="house">Gryffindor</label>
      <label><input type="radio" name="house" checked>Hufflepuff</label>
      <label><input type="checkbox" value="">Portkey</label>
      """

      with_html(unquote(driver), html, fn session ->
        for name <- ["Owl post", "Floo powder", "Gryffindor", "Hufflepuff"] do
          assert input_value(session, by_label(name)) == "on"
          expect(session, to_have_value(by_label(name), "on"))
        end

        assert input_value(session, by_label("Portkey")) == ""
      end)
    end

    @tag driver: driver
    test "reads are strict and fail without a target with #{driver}" do
      html = "<p>Lumos</p><p>Lumos</p>"

      with_html(unquote(driver), html, fn session ->
        reads = [
          text_content: &text_content(session, &1, timeout: &2),
          get_attribute: &get_attribute(session, &1, "id", timeout: &2),
          input_value: &input_value(session, &1, timeout: &2)
        ]

        for {operation, read} <- reads do
          error = assert_raise Fluffy.OperationError, fn -> read.(by_text("Lumos"), 1_000) end
          assert error.operation == operation
          assert strictness_error?(error)

          error = assert_raise Fluffy.OperationError, fn -> read.(by_text("Nox"), 100) end
          assert error.operation == operation
        end
      end)
    end
  end

  test "inner_text and all_inner_texts read the rendered text on Playwright" do
    html = ~s(<ul><li>Fluffy <span style="display: none">hidden</span>dog</li><li>Norbert</li></ul>)

    with_html(:playwright, html, fn session ->
      assert Fluffy.Playwright.inner_text(session, first(by_css("li"))) == "Fluffy dog"
      assert Fluffy.Playwright.all_inner_texts(session, by_css("li")) == ["Fluffy dog", "Norbert"]
      assert Fluffy.Playwright.all_inner_texts(session, by_css("li.missing")) == []
    end)
  end

  test "inner_text and all_inner_texts need a browser on Phoenix" do
    with_html(:static, "<p>Lumos</p>", fn session ->
      for read <- [&Fluffy.Playwright.inner_text(session, &1), &Fluffy.Playwright.all_inner_texts(session, &1)] do
        error = assert_raise Fluffy.CapabilityError, fn -> read.(by_text("Lumos")) end
        assert error.capability == :computed_browser_semantics
      end
    end)
  end

  for driver <- Drivers.backends() do
    @tag driver: driver
    test "reads wait for their target to attach with #{driver}", %{driver: driver} do
      appearing = by_role(:button, name: "Appearing action")

      session =
        driver
        |> start_session()
        |> visit("/live/action-retries")
        |> click(by_role(:button, name: "Release appearing button"))

      assert get_attribute(session, appearing, "phx-value-kind") == "appeared"
      assert session |> text_content(appearing) |> String.trim() == "Appearing action"
    end

    @tag driver: driver
    test "a LiveView checkbox without a value reads \"on\", checked or not, with #{driver}", %{driver: driver} do
      tonic = by_label("Reveal Phoenix Tonic")

      session =
        driver
        |> start_session()
        |> visit("/live/action-retries")
        |> expect(to_have_value(tonic, "on"))

      assert input_value(session, tonic) == "on"

      session = session |> check(tonic) |> expect(to_have_value(tonic, "on"))
      assert input_value(session, tonic) == "on"
    end

    @tag driver: driver
    test "input_value reads the LiveView form's current value with #{driver}", %{driver: driver} do
      session =
        driver
        |> start_session()
        |> visit("/live/potions")
        |> fill(by_label("First ingredient"), "ash")
        |> expect(to_be_visible(by_text("Last first: ash")))

      assert input_value(session, by_label("First ingredient")) == "ash"
    end

    @tag driver: driver
    test "LiveView reads are strict and need a control for input_value with #{driver}", %{driver: driver} do
      session = driver |> start_session() |> visit("/live/potions")

      error = assert_raise Fluffy.OperationError, fn -> text_content(session, by_css("input"), timeout: 1_000) end
      assert error.operation == :text_content
      assert strictness_error?(error)

      error = assert_raise Fluffy.OperationError, fn -> input_value(session, by_css("#wizard-form"), timeout: 1_000) end
      assert error.operation == :input_value
      assert Exception.message(error) =~ "Node is not an <input>, <textarea> or <select> element"
    end
  end

  defp strictness_error?(%{backend: :phoenix, cause: cause}),
    do: match?(%Fluffy.StrictnessError{candidates: [_, _ | _]}, cause)

  defp strictness_error?(%{backend: :playwright} = error), do: Exception.message(error) =~ "strict mode violation"
end
