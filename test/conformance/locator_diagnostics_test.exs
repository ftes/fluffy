defmodule Fluffy.Conformance.LocatorDiagnosticsTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- Drivers.html() do
    @tag driver: driver
    test "count failures describe the public locator with backend-native diagnostics with #{driver}" do
      session =
        session_for_html(
          unquote(driver),
          "<button>Save</button><button>Save draft</button>"
        )

      error =
        assert_raise ExUnit.AssertionError, fn ->
          expect(session, :button |> by_role(name: "Save") |> to_have_count(1), timeout: 1_000)
        end

      assert error.message =~ "by_role(:button, name: \"Save\")"

      if unquote(driver) == :playwright do
        assert error.message =~ "Received: 2"
        assert error.message =~ "Call log:"
      else
        assert error.message =~ "it matched 2"
        assert error.message =~ "<button>Save</button>"
        assert error.message =~ "<button>Save draft</button>"
      end
    end

    @tag driver: driver
    test "rejects unsupported assertion options with #{driver}" do
      session =
        session_for_html(unquote(driver), "<button>Save</button>")

      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:eventually/, fn ->
        expect(session, :button |> by_role(name: "Save") |> to_have_count(1), eventually: true)
      end
    end
  end

  test "Static click rejects an ambiguous locator" do
    session = session_for_html(:static, "<button>Save</button><button>Save draft</button>")
    locator = by_role(:button, name: "Save")

    error =
      assert_raise Fluffy.OperationError, fn ->
        click(session, locator)
      end

    assert error.message =~ "resolve to exactly one element"
    assert error.message =~ "it matched 2"
    assert error.message =~ "<button>Save draft</button>"
  end

  test "Static click suggests accessible names within the missing role's scope" do
    session =
      session_for_html(:static, """
      <section><button aria-labelledby="spell">Cast</button><button hidden>Nox</button></section>
      <span id="spell">Lumos</span><button>Accio</button>
      """)

    locator = within(by_role(:button, "Expelliarmus"), by_css("section"))
    error = assert_raise Fluffy.OperationError, fn -> click(session, locator) end

    assert %Fluffy.StrictnessError{locator: ^locator, candidates: []} = error.cause
    assert error.message =~ "No element matched"
    assert error.message =~ ~s(Other button names in scope: "Lumos")
    refute error.message =~ "Cast"
    refute error.message =~ "Nox"
    refute error.message =~ "Accio"
  end

  test "visibility failures distinguish a hidden match from a missing element" do
    session = session_for_html(:static, ~s(<button hidden>Stupefy</button>))

    hidden = assert_raise ExUnit.AssertionError, fn -> expect(session, to_be_visible(by_css("button"))) end
    assert hidden.message =~ "Matched a hidden element: <button hidden"
    assert hidden.message =~ "Stupefy</button>"

    missing = assert_raise ExUnit.AssertionError, fn -> expect(session, not_(to_be_hidden(by_css("a")))) end
    assert missing.message =~ "No element matched."
    refute missing.message =~ "Matched a hidden element"
  end

  test "missing named roles show accessible names from the requested scope" do
    session =
      session_for_html(:static, """
      <section><button aria-label="Lumos">Cast</button><button hidden>Nox</button></section>
      <button>Accio</button>
      """)

    scope = by_css("section")
    role = by_role(:button, "Expelliarmus")

    for locator <- [by_role(scope, :button, "Expelliarmus"), within(role, scope)] do
      error = assert_raise ExUnit.AssertionError, fn -> expect(session, to_be_visible(locator)) end
      assert error.message =~ Fluffy.Locator.Internal.describe(locator)
      assert error.message =~ ~s(Other button names in scope: "Lumos")
      refute error.message =~ "Cast"
      refute error.message =~ "Nox"
      refute error.message =~ "Accio"
    end
  end

  @tag driver: :playwright
  test "Playwright actions retain native ambiguity diagnostics" do
    session =
      session_for_html(:playwright, "<button>Save</button><button>Save draft</button>")

    assert_raise Fluffy.OperationError, ~r/strict mode violation/, fn ->
      click(session, by_role(:button, name: "Save"))
    end
  end

  test "Static role locators ignore CSS-computed visibility" do
    html = "<style>.hidden { display: none }</style><button class=\"hidden\">Hidden</button>"
    locator = by_role(:button, name: "Hidden")

    static_session = session_for_html(:static, html)

    expect(static_session, to_have_count(locator, 1))
  end
end
