defmodule Fluffy.Conformance.FieldDiagnosticsTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Locator

  test "missing fill suggests effective labels of fields in the locator's scope" do
    session =
      session_for_html(:static, """
      <span id="owl">Post owl</span>
      <section>
        <label for="name">Wizard</label>
        <input id="name" aria-label="Superseded" aria-labelledby="owl">
        <label>Spell <textarea></textarea></label>
        <input aria-label="House">
      </section>
      <input aria-label="Outside">
      """)

    scope = by_css("section")

    for locator <- [by_label(scope, "Wand"), within(by_label("Wand"), scope)] do
      error = assert_raise Fluffy.OperationError, fn -> fill(session, locator, "Holly") end
      assert %Fluffy.StrictnessError{candidates: [], locator: ^locator} = error.cause
      assert error.message =~ ~s(Other labels in scope: "Post owl", "Spell", "House")
      refute error.message =~ "Wizard"
      refute error.message =~ "Superseded"
      refute error.message =~ "Outside"
    end
  end

  test "a matching HTML label is reported as unassociated only when it has no control anywhere" do
    session =
      session_for_html(:static, """
      <section>
        <label for="missing">Wand   wood</label>
        <label for="outside">Core</label>
        <label>Length<input aria-label="Inches"></label>
      </section>
      <input id="outside">
      """)

    scope = by_css("section")

    for text <- ["wand wood", ~r/^Wand +wood$/] do
      error = assert_raise Fluffy.OperationError, fn -> fill(session, by_label(scope, text), "Ash") end
      assert error.message =~ ~s|A matching label ("Wand wood") has no associated control.|
    end

    for locator <- [by_label(scope, "wand wood", exact: true), by_label(scope, "Core"), by_label(scope, "Length")] do
      error = assert_raise Fluffy.OperationError, fn -> fill(session, locator, "Ash") end
      refute error.message =~ "no associated control"
    end
  end

  test "an index after by_label can miss even when the labelled field exists" do
    session = session_for_html(:static, ~s(<label>Wand <input></label><label>Owl <input></label>))
    locator = "Wand" |> by_label() |> nth(1)
    error = assert_raise Fluffy.OperationError, fn -> fill(session, locator, "Ash") end

    refute error.message =~ "Other labels"
    refute error.message =~ "no associated control"
  end

  test "a missing LiveView fill retains the strictness cause and reports other field labels" do
    session = :phoenix |> start_session() |> visit("/live/mystic-creatures")
    locator = by_label(by_css("#actionability-form"), "Wand wood")
    error = assert_raise Fluffy.OperationError, fn -> fill(session, locator, "Ash", timeout: :once) end

    assert %Fluffy.StrictnessError{candidates: [], locator: ^locator} = error.cause
    assert error.message =~ ~s(Other labels in scope: "Search bestiary")
  end
end
