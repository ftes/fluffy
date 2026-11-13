defmodule Fluffy.Conformance.AccessibilityExpectationTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  # Role, accessible name and description assertions, which Phoenix computes with
  # its port of getAriaRole, getElementAccessibleName and
  # getElementAccessibleDescription (roleUtils.ts). The cases follow upstream's
  # expect-to-have-accessible.spec.ts.
  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "to_have_role reads explicit and implicit roles with #{driver}" do
      html = """
      <div data-testid="explicit" role="button">Button!</div>
      <a data-testid="link" href="/hogwarts">Hogwarts</a>
      <a data-testid="anchor">Anchor</a>
      <input data-testid="search" type="search">
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> expect("explicit" |> by_test_id() |> to_have_role(:button))
        |> expect("explicit" |> by_test_id() |> to_have_role(:checkbox) |> not_())
        |> expect("link" |> by_test_id() |> to_have_role(:link))
        |> expect("anchor" |> by_test_id() |> to_have_role(:link) |> not_())
        |> expect("search" |> by_test_id() |> to_have_role(:searchbox))
      end)
    end

    @tag driver: driver
    test "to_have_accessible_name matches the flat name with #{driver}" do
      html = """
      <div data-testid="labelled" role="button" aria-label="Hello"></div>
      <button data-testid="content">foo&nbsp;bar
      baz</button>
      <select><option data-testid="option">&nbsp;HTML</option></select>
      <span id="first">Expecto</span><span id="second">Patronum</span>
      <button data-testid="referenced" aria-labelledby="first second">Cast</button>
      <label for="wand">Wand</label><input data-testid="wand" id="wand">
      <p data-testid="paragraph" aria-label="Prohibited">Text</p>
      """

      with_html(unquote(driver), html, fn session ->
        labelled = by_test_id("labelled")

        session
        |> expect(to_have_accessible_name(labelled, "Hello"))
        |> expect(labelled |> to_have_accessible_name("hello") |> not_())
        |> expect(to_have_accessible_name(labelled, "hello", ignore_case: true))
        |> expect(to_have_accessible_name(labelled, ~r/ell\w/))
        |> expect(labelled |> to_have_accessible_name(~r/hello/) |> not_())
        |> expect(to_have_accessible_name(labelled, ~r/hello/, ignore_case: true))
        |> expect("content" |> by_test_id() |> to_have_accessible_name("foo bar baz"))
        |> expect("option" |> by_test_id() |> to_have_accessible_name("HTML"))
        |> expect("referenced" |> by_test_id() |> to_have_accessible_name("Expecto Patronum"))
        |> expect("wand" |> by_test_id() |> to_have_accessible_name("Wand"))
        |> expect("paragraph" |> by_test_id() |> to_have_accessible_name(""))
      end)
    end

    @tag driver: driver
    test "to_have_accessible_description follows describedby, description and title with #{driver}" do
      html = """
      <div data-testid="described" role="button" aria-description="Hello"></div>
      <div data-testid="referenced" role="button" aria-describedby="desc missing"></div>
      <span id="desc">foo&nbsp;bar
      baz</span>
      <span id="hidden" hidden>Under the <b>cloak</b></span>
      <input data-testid="hidden-reference" aria-describedby="hidden" title="Ignored">
      <button data-testid="titled" title="Lumos">Light</button>
      <button data-testid="invalid" aria-describedby="missing" title="Ignored">Light</button>
      """

      with_html(unquote(driver), html, fn session ->
        described = by_test_id("described")

        session
        |> expect(to_have_accessible_description(described, "Hello"))
        |> expect(described |> to_have_accessible_description("hello") |> not_())
        |> expect(to_have_accessible_description(described, "hello", ignore_case: true))
        |> expect(to_have_accessible_description(described, ~r/ell\w/))
        |> expect("referenced" |> by_test_id() |> to_have_accessible_description("foo bar baz"))
        |> expect("hidden-reference" |> by_test_id() |> to_have_accessible_description("Under the cloak"))
        |> expect("titled" |> by_test_id() |> to_have_accessible_description("Lumos"))
        |> expect("invalid" |> by_test_id() |> to_have_accessible_description(""))
      end)
    end
  end

  defp with_html(driver, html, fun) do
    session = session_for_html(driver, html, base_url: Fluffy.Support.Server.base_url())
    fun.(session)
  end
end
