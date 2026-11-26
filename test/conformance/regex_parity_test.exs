defmodule Fluffy.Conformance.RegexParityTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Support.Web.ExpectationsLive
  alias Playwright.RegExp

  @constructors [:by_text, :by_label, :by_placeholder, :by_alt_text, :by_title, :by_test_id]

  for driver <- Drivers.all() do
    @tag driver: driver
    test "#{driver} matches raw locator text with both regex types", %{driver: driver} do
      session = session(driver)
      scope = by_css("#spellbook")

      for constructor <- @constructors do
        for pattern <- [~r/spell  book/i, RegExp.new("spell[^] book", "i")] do
          expect(session, to_have_count(regex_locator(constructor, [pattern]), 1))
          expect(session, to_have_count(regex_locator(constructor, [scope, pattern]), 1))
        end

        expect(session, to_have_count(regex_locator(constructor, [~r/spell book/i]), 0))
      end
    end

    @tag driver: driver
    test "#{driver} matches raw input and ordered multi-select values", %{driver: driver} do
      spell = by_css("#spell")
      potions = by_css("#potions")

      driver
      |> session()
      |> expect(to_have_value(spell, ~r/^lumos  /i))
      |> expect(Fluffy.Assert.value(spell, RegExp.new("lumos[^] maxima$", "i")))
      |> expect(not_(to_have_value(spell, ~r/Lumos Maxima/)))
      |> select_option(potions, ["veritaserum", "felix  felicis", "polyjuice"])
      |> expect(to_have_values(potions, ["polyjuice", ~r/^felix  /, RegExp.new("^verita")]))
      |> expect(not_(to_have_values(potions, [~r/^felix/, "polyjuice", "veritaserum"])))
      |> expect(not_(Fluffy.Assert.values(potions, ["polyjuice", ~r/^felix/])))
    end
  end

  for driver <- Drivers.html() do
    @tag driver: driver
    test "#{driver} text regexes can match both an ancestor and a grandchild", %{driver: driver} do
      driver
      |> session_for_html("<div id='lesson'>Lumos <div>Repeat: <b>Lumos</b></div></div>")
      |> expect(to_have_count(by_text(by_css("#lesson"), ~r/^Lumos/), 2))
    end
  end

  for backend <- Drivers.backends() do
    @tag driver: backend
    test "#{backend} text regexes omit the document head", %{driver: backend} do
      backend
      |> start_session()
      |> visit("/chamber")
      |> expect(to_have_count(by_text(~r/Sleeping chamber/), 0))
    end
  end

  @tag driver: :playwright
  test "locators accept both regex types in a frame" do
    html = ExpectationsLive.markup() |> String.replace("&", "&amp;") |> String.replace("\"", "&quot;")
    session = session_for_html(:playwright, ~s(<iframe id="library" srcdoc="#{html}"></iframe>))
    frame = frame_locator("#library")

    for constructor <- @constructors,
        pattern <- [~r/spell  book/i, RegExp.new("spell[^] book", "i")] do
      arguments = [frame, pattern]
      expect(session, to_have_count(apply(Fluffy.Locator, constructor, arguments), 1))
      expect(session, to_have_count(regex_locator(constructor, arguments), 1))
    end
  end

  defp regex_locator(:by_test_id, arguments), do: apply(Fluffy.Locator, :by_test_id, arguments)
  defp regex_locator(constructor, arguments), do: apply(Fluffy.Locator, constructor, arguments ++ [[exact: true]])

  defp session(:live), do: :phoenix |> start_session() |> visit("/live/expectations")
  defp session(driver), do: session_for_html(driver, ExpectationsLive.markup())
end
