defmodule Fluffy.Conformance.FormCapabilityTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestHTTPFixtures
  alias Fluffy.TestWeb.Endpoint

  test "Static bypasses native constraint validation and submits structurally" do
    fixture =
      TestHTTPFixtures.register_sequence([
        %{
          body: html(~s(<form action="submitted"><input name="email" required><button>Save</button></form>))
        },
        %{body: html("<h1>Submitted</h1>")}
      ])

    :phoenix
    |> start_session(
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Endpoint
    )
    |> visit(TestHTTPFixtures.path(fixture, "/start"))
    |> click(by_role(:button, name: "Save"))
    |> expect(visible(by_text("Submitted")))
  end

  test "Live bypasses native constraint validation and submits structurally" do
    :phoenix
    |> start_session(
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Endpoint
    )
    |> visit("/live/potions")
    |> click(by_role(:button, name: "Seal required potion"))
    |> expect(visible(by_text("Constrained form submitted")))
  end

  @tag driver: :playwright
  test "Playwright submit runs native constraint validation" do
    session =
      session_for_html(
        :playwright,
        """
        <form id="profile" onsubmit="event.preventDefault(); result.value = 'submitted'">
          <label>Email <input name="email" required></label>
          <button>Save</button>
        </form>
        <input id="result" aria-label="Result" value="waiting">
        """
      )

    session
    |> submit(by_css("#profile"))
    |> expect(value(by_label("Result"), "waiting"))
    |> fill(by_label("Email"), "person@example.test")
    |> submit(by_css("#profile"))
    |> expect(value(by_label("Result"), "submitted"))
  end

  test "Static names computed dirname submission as unsupported" do
    session =
      session_for_html(
        :static,
        ~s(<form><input name="comment" dirname="comment.dir"><button>Save</button></form>)
      )

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        click(session, by_role(:button, name: "Save"))
      end

    assert error.capability == :form_directionality
  end

  test "Static names text/plain encoding as unsupported" do
    session =
      session_for_html(
        :static,
        ~s(<form method="post" enctype="text/plain"><button>Save</button></form>)
      )

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        click(session, by_role(:button, name: "Save"))
      end

    assert error.capability == :form_encoding
  end

  test "Static names hard textarea wrapping as unsupported" do
    session =
      session_for_html(
        :static,
        ~s(<form><textarea name="notes" wrap="hard"></textarea><button>Save</button></form>)
      )

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        click(session, by_role(:button, name: "Save"))
      end

    assert error.capability == :textarea_hard_wrap
  end

  test "Static names form-associated custom elements as unsupported" do
    session =
      session_for_html(
        :static,
        ~s(<form><date-picker name="date"></date-picker><button>Save</button></form>)
      )

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        click(session, by_role(:button, name: "Save"))
      end

    assert error.capability == :form_associated_elements
  end

  test "Static names scripted form entry mutation as unsupported" do
    session =
      session_for_html(
        :static,
        ~S|<form onformdata="event.formData.append('extra', 'yes')"><button>Save</button></form>|
      )

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        click(session, by_role(:button, name: "Save"))
      end

    assert error.capability == :scripted_form_submission
  end

  defp html(body), do: "<!doctype html><html><body><main>#{body}</main></body></html>"
end
