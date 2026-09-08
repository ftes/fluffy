defmodule Fluffy.Conformance.ActionabilityCapabilityTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestWeb.Endpoint

  for driver <- [:static, :playwright] do
    @tag driver: driver
    @tag :webkit_difference
    test "click ignores unrelated layout-sensitive stylesheet rules with #{driver}" do
      html =
        ~s(<style>.unrelated { min-width: 1px; }</style><div class="unrelated" style="min-width: 1px"></div><button>Save</button>)

      with_html(unquote(driver), html, fn session ->
        session
        |> click(by_role(:button, name: "Save"))
        |> expect(focused(by_role(:button, name: "Save")))
      end)
    end
  end

  test "Static ignores target inline width when clicking structurally" do
    session = session_for_html(:static, ~s(<button style="width: 1px">Save</button>))

    session
    |> click(by_role(:button, name: "Save"))
    |> expect(focused(by_role(:button, name: "Save")))
  end

  test "Static ignores ancestor inline height when filling structurally" do
    session =
      session_for_html(
        :static,
        ~s(<div style="height: 1px"><label>Name <input></label></div>)
      )

    session
    |> fill(by_label("Name"), "Ada")
    |> expect(value(by_label("Name"), "Ada"))
  end

  test "Static ignores matching stylesheet rules when clicking structurally" do
    session =
      session_for_html(
        :static,
        ~s(<style>.target { opacity: 0; }</style><button class="target">Save</button>)
      )

    session
    |> click(by_role(:button, name: "Save"))
    |> expect(focused(by_role(:button, name: "Save")))
  end

  test "Static ignores unparsed stylesheet rules when clicking structurally" do
    session =
      session_for_html(
        :static,
        ~S|<style>@media (min-width: 1px) { .target { opacity: 0; } }</style><button class="target">Save</button>|
      )

    session
    |> click(by_role(:button, name: "Save"))
    |> expect(focused(by_role(:button, name: "Save")))
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "fill ignores unrelated layout-sensitive markup in a LiveView with #{driver}" do
      session =
        start_session(unquote(driver),
          base_url: Fluffy.TestServer.base_url(),
          endpoint: Endpoint
        )

      session
      |> visit("/live/mystic-creatures")
      |> fill(by_label("Search bestiary"), "phoenix")
      |> expect(visible(by_text("Bestiary search: phoenix", exact: true)))
    end

    @tag driver: driver
    test "checking survives minimum-dimension ancestors in a LiveView with #{driver}" do
      checkbox = by_label("Accounts", exact: true)

      session =
        start_session(unquote(driver),
          base_url: Fluffy.TestServer.base_url(),
          endpoint: Endpoint
        )

      session
      |> visit("/live/mystic-creatures")
      |> check(checkbox)
      |> expect(checked(checkbox))
      |> expect(visible(by_text("Accounts: checked", exact: true)))
    end
  end

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "checking survives minimum-dimension ancestors with #{driver}" do
      checkbox = by_label("Accounts", exact: true)

      html =
        ~s(<div style="min-width: 100%; min-height: 1px"><label>Accounts <input type="checkbox"></label></div>)

      with_html(unquote(driver), html, fn session ->
        session
        |> check(checkbox)
        |> expect(checked(checkbox))
      end)
    end
  end

  defp with_html(driver, html, fun) do
    session = session_for_html(driver, html, base_url: Fluffy.TestServer.base_url())
    fun.(session)
  end
end
