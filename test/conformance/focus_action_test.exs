defmodule Fluffy.Conformance.FocusActionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "focusing another control implicitly blurs the previous control with #{driver}" do
      first = by_label("First")
      second = by_label("Second")
      html = ~s(<input aria-label="First"><input aria-label="Second">)

      with_html(unquote(driver), html, fn session ->
        session
        |> focus(first)
        |> expect(focused(first))
        |> focus(second)
        |> expect(not_(focused(first)))
        |> expect(focused(second))
      end)
    end

    @tag driver: driver
    test "blurring an unfocused control preserves the active control with #{driver}" do
      first = by_label("First")
      second = by_label("Second")
      html = ~s(<input aria-label="First"><input aria-label="Second">)

      with_html(unquote(driver), html, fn session ->
        session
        |> focus(first)
        |> blur(second)
        |> expect(focused(first))
        |> blur(first)
        |> expect(not_(focused(first)))
      end)
    end

    @tag driver: driver
    test "focusing a non-focusable element leaves focus unchanged with #{driver}" do
      field = by_label("Name")
      note = by_text("Read only note", exact: true)
      html = ~s(<input aria-label="Name"><div>Read only note</div>)

      with_html(unquote(driver), html, fn session ->
        session
        |> focus(field)
        |> focus(note)
        |> expect(focused(field))
        |> expect(not_(focused(note)))
      end)
    end

    @tag driver: driver
    test "select_option does not add an unobserved focus transition with #{driver}" do
      field = by_label("Name")
      plan = by_label("Plan")

      html = """
      <input aria-label="Name">
      <select aria-label="Plan"><option>Free</option><option>Pro</option></select>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> focus(field)
        |> select_option(plan, "Pro")
        |> expect(focused(field))
        |> expect(not_(focused(plan)))
      end)
    end

    @tag driver: driver
    test "a control disabled by its fieldset cannot receive focus with #{driver}" do
      html = """
      <input aria-label="Current">
      <fieldset disabled><input aria-label="Blocked"></fieldset>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> focus(by_label("Current"))
        |> focus(by_label("Blocked"))
        |> expect(focused(by_label("Current")))
        |> expect(not_(focused(by_label("Blocked"))))
      end)
    end
  end

  defp with_html(driver, html, fun) do
    session = session_for_html(driver, html, base_url: Fluffy.TestServer.base_url())
    fun.(session)
  end
end
