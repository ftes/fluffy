defmodule Fluffy.Conformance.FocusActionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  @tag driver: :playwright
  test "focusing another control implicitly blurs the previous control with playwright" do
    first = by_label("First")
    second = by_label("Second")
    html = ~s(<input aria-label="First"><input aria-label="Second">)

    with_html(:playwright, html, fn session ->
      session
      |> focus(first)
      |> expect(to_be_focused(first))
      |> focus(second)
      |> expect(not_(to_be_focused(first)))
      |> expect(to_be_focused(second))
    end)
  end

  @tag driver: :playwright
  test "blurring an unfocused control preserves the active control with playwright" do
    first = by_label("First")
    second = by_label("Second")
    html = ~s(<input aria-label="First"><input aria-label="Second">)

    with_html(:playwright, html, fn session ->
      session
      |> focus(first)
      |> blur(second)
      |> expect(to_be_focused(first))
      |> blur(first)
      |> expect(not_(to_be_focused(first)))
    end)
  end

  @tag driver: :playwright
  test "focusing a non-focusable element leaves focus unchanged with playwright" do
    field = by_label("Name")
    note = by_text("Read only note", exact: true)
    html = ~s(<input aria-label="Name"><div>Read only note</div>)

    with_html(:playwright, html, fn session ->
      session
      |> focus(field)
      |> focus(note)
      |> expect(to_be_focused(field))
      |> expect(not_(to_be_focused(note)))
    end)
  end

  @tag driver: :playwright
  test "select_option does not add an unobserved focus transition with playwright" do
    field = by_label("Name")
    plan = by_label("Plan")

    html = """
    <input aria-label="Name">
    <select aria-label="Plan"><option>Free</option><option>Pro</option></select>
    """

    with_html(:playwright, html, fn session ->
      session
      |> focus(field)
      |> select_option(plan, "Pro")
      |> expect(to_be_focused(field))
      |> expect(not_(to_be_focused(plan)))
    end)
  end

  @tag driver: :playwright
  test "a control disabled by its fieldset cannot receive focus with playwright" do
    html = """
    <input aria-label="Current">
    <fieldset disabled><input aria-label="Blocked"></fieldset>
    """

    with_html(:playwright, html, fn session ->
      session
      |> focus(by_label("Current"))
      |> focus(by_label("Blocked"))
      |> expect("Current" |> by_label() |> to_be_focused())
      |> expect("Blocked" |> by_label() |> to_be_focused() |> not_())
    end)
  end

  for driver <- [:static, :live] do
    test "#{driver} rejects focus actions and assertions, including negation" do
      session =
        case unquote(driver) do
          :static -> session_for_html(:static, ~s(<input aria-label="Name">))
          :live -> :phoenix |> start_session() |> visit("/live/potions")
        end

      locator = by_css("input")

      for action <- [
            fn -> focus(session, locator) end,
            fn -> blur(session, locator) end,
            fn -> expect(session, to_be_focused(locator)) end,
            fn -> expect(session, not_(to_be_focused(locator))) end
          ] do
        error = assert_raise Fluffy.CapabilityError, action
        assert error.driver == unquote(driver)
      end
    end
  end

  @tag driver: :playwright
  test "browser fill and click update focus" do
    with_html(:playwright, ~s(<input aria-label="Name"><button>Save</button>), fn session ->
      session
      |> fill(by_label("Name"), "Ada")
      |> expect(to_be_focused(by_label("Name")))
      |> click(by_role(:button, name: "Save"))
      |> expect(to_be_focused(by_role(:button, name: "Save")))
    end)
  end

  defp with_html(driver, html, fun) do
    session = session_for_html(driver, html, base_url: Fluffy.TestServer.base_url())
    fun.(session)
  end
end
