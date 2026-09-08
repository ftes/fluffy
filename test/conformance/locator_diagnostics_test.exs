defmodule Fluffy.Conformance.LocatorDiagnosticsTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Locator.Static, as: StaticLocator

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "count failures describe the public locator and candidates with #{driver}" do
      session =
        session_for_html(
          unquote(driver),
          "<button>Save</button><button>Save draft</button>",
          base_url: Fluffy.TestServer.base_url()
        )

      error =
        assert_raise ExUnit.AssertionError, fn ->
          expect(session, :button |> by_role(name: "Save") |> to_have_count(1), timeout: 0)
        end

      assert error.message =~ "by_role(:button, name: \"Save\")"
      assert error.message =~ "it matched 2"
      assert error.message =~ "<button>Save</button>"
      assert error.message =~ "<button>Save draft</button>"
    end

    @tag driver: driver
    test "rejects unsupported assertion options with #{driver}" do
      session =
        session_for_html(unquote(driver), "<button>Save</button>", base_url: Fluffy.TestServer.base_url())

      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:eventually/, fn ->
        expect(session, :button |> by_role(name: "Save") |> to_have_count(1), eventually: true)
      end
    end
  end

  test "fast single-target resolution rejects an ambiguous locator" do
    document = LazyHTML.from_fragment("<button>Save</button><button>Save draft</button>")
    locator = by_role(:button, name: "Save")

    error =
      assert_raise Fluffy.StrictnessError, fn ->
        StaticLocator.resolve_one!(document, locator)
      end

    assert error.message =~ "resolve to exactly one element"
    assert error.message =~ "it matched 2"
    assert error.message =~ "<button>Save draft</button>"
  end

  test "fast single-target resolution rejects a missing locator" do
    document = LazyHTML.from_fragment("<button>Cancel</button>")

    assert_raise Fluffy.StrictnessError, ~r/it matched 0.*Candidates: none/s, fn ->
      StaticLocator.resolve_one!(document, by_role(:button, name: "Save", exact: true))
    end
  end

  @tag driver: :playwright
  test "Playwright actions translate ambiguity to the canonical strictness error" do
    session =
      session_for_html(:playwright, "<button>Save</button><button>Save draft</button>",
        base_url: Fluffy.TestServer.base_url()
      )

    assert_raise Fluffy.StrictnessError, ~r/it matched 2/, fn ->
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
