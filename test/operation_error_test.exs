defmodule Fluffy.OperationErrorTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.OperationError
  alias Fluffy.Playwright

  test "retains structured error names and the complete original error" do
    locator = by_role(:button, name: "Save")

    for name <- ["TimeoutError", "TargetClosedError"] do
      original = %{error: %{name: name, message: "original message", stack: "original stack"}, log: ["waiting for Save"]}

      error =
        OperationError.exception(
          backend: :playwright,
          driver: :playwright,
          operation: :click,
          locator: locator,
          cause: original
        )

      assert error.operation == :click
      assert error.locator == locator
      assert error.cause == original
      assert error.message =~ name
      assert error.message =~ "original message"
      assert error.message =~ "waiting for Save"
    end
  end

  @tag driver: :playwright
  test "submit retains native errors for non-forms and ambiguous form queries" do
    session = browser_html("<div>Not a form</div><form></form><form></form>")

    for {selector, message} <- [{"div", "requires a form locator"}, {"form", "strict mode violation"}] do
      locator = by_css(selector)
      error = assert_raise OperationError, fn -> submit(session, locator) end
      assert error.operation == :submit
      assert error.locator == locator
      assert %{error: %{name: "Error"}} = error.cause
      assert error.message =~ message
    end
  end

  @tag driver: :playwright
  test "assertion diagnostics retain received state and do not clone custom elements" do
    session = browser_html("<section><review-element></review-element></section>")

    Playwright.evaluate(
      session,
      """
      () => {
        window.constructions = 0;
        customElements.define('review-element', class extends HTMLElement {
          constructor() { super(); window.constructions++; }
        });
      }
      """,
      is_function: true
    )

    before = Playwright.evaluate(session, "window.constructions")

    error =
      assert_raise ExUnit.AssertionError, fn ->
        expect(session, to_have_count(by_css("section"), 2), timeout: 200)
      end

    assert error.message =~ "to have count 2"
    assert error.message =~ "value: 1"
    assert error.message =~ "timed_out: true"
    assert error.message =~ "Call log:"
    assert Playwright.evaluate(session, "window.constructions") == before
  end

  @tag driver: :playwright
  test "action errors need no second read of the document" do
    session = browser_html("<button disabled>Save</button>")

    Playwright.evaluate(
      session,
      """
      () => {
        Element.prototype.cloneNode = () => { throw new Error('unexpected diagnostic clone') };
      }
      """,
      is_function: true
    )

    locator = by_role(:button, name: "Save")
    error = assert_raise OperationError, fn -> click(session, locator, timeout: 200) end
    assert error.operation == :click
    assert error.locator == locator
    assert %{error: %{name: "TimeoutError"}} = error.cause
    assert error.message =~ "Call log:"
    refute error.message =~ "unexpected diagnostic clone"
  end

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "operation context and native causes are preserved with #{driver}" do
      session =
        session_for_html(
          unquote(driver),
          "<button disabled>Save</button><input type='checkbox' disabled aria-label='Updates'>",
          base_url: Fluffy.TestServer.base_url()
        )

      button = by_role(:button, name: "Save")
      checkbox = by_role(:checkbox, name: "Updates")

      for {operation, locator, action} <- [
            {:click, button, fn -> click(session, button, timeout: 50) end},
            {:check, checkbox, fn -> check(session, checkbox, timeout: 50) end}
          ] do
        error = assert_raise OperationError, action
        assert error.operation == operation
        assert error.locator == locator
        assert error.driver == unquote(driver)

        if unquote(driver) == :playwright do
          assert error.backend == :playwright
          assert %{error: %{name: "TimeoutError"}, log: [_ | _]} = error.cause
        else
          assert error.backend == :phoenix
          assert %Fluffy.ActionabilityError{reason: :disabled, locator: ^locator} = error.cause
        end
      end

      assert_raise NimbleOptions.ValidationError, fn -> click(session, button, unsupported: true) end
      assert_raise ExUnit.AssertionError, fn -> expect(session, to_have_count(button, 2), timeout: 50) end

      session =
        if unquote(driver) == :static do
          :phoenix |> start_session(endpoint: Fluffy.TestWeb.Endpoint) |> visit("/chamber")
        else
          session
        end

      original = RuntimeError.exception("user callback failed")
      assert ^original = assert_raise(RuntimeError, fn -> unwrap(session, fn _ -> raise original end) end)
      structural = Fluffy.StrictnessError.exception(locator: button, candidates: [])
      assert ^structural = assert_raise(Fluffy.StrictnessError, fn -> unwrap(session, fn _ -> raise structural end) end)
    end
  end

  test "Phoenix singular assertion failures stay ExUnit assertions" do
    session = session_for_html(:static, "<button>Save</button><button>Save</button>")

    assert_raise ExUnit.AssertionError, ~r/matched 2/, fn ->
      expect(session, to_be_enabled(by_role(:button, name: "Save")))
    end
  end

  defp browser_html(html) do
    session_for_html(:playwright, html, base_url: Fluffy.TestServer.base_url())
  end
end
