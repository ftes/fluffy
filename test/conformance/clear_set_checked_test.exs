defmodule Fluffy.Conformance.ClearSetCheckedTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "clear empties text inputs and textareas with #{driver}" do
      html = ~s(<input aria-label="Name" value="Ron"><textarea aria-label="Notes">Lumos</textarea>)

      with_html(unquote(driver), html, fn session ->
        session
        |> clear(by_label("Name"))
        |> clear(by_label("Notes"))
        |> expect(to_have_value(by_label("Name"), ""))
        |> expect(to_have_value(by_label("Notes"), ""))
      end)
    end

    @tag driver: driver
    test "clear fails on a field that cannot be edited with #{driver}" do
      html = ~s(<input aria-label="Sealed" value="Ron" readonly><p id="prose">Text</p>)

      with_html(unquote(driver), html, fn session ->
        for locator <- [by_label("Sealed"), by_css("#prose")] do
          error = assert_raise Fluffy.OperationError, fn -> clear(session, locator, timeout: 100) end
          assert error.operation == :clear
        end

        expect(session, to_have_value(by_label("Sealed"), "Ron"))
      end)
    end

    @tag driver: driver
    test "set_checked sets the requested state and is idempotent with #{driver}" do
      checkbox = by_role(:checkbox, name: "Updates")
      html = ~s(<label><input type="checkbox">Updates</label>)

      with_html(unquote(driver), html, fn session ->
        session
        |> set_checked(checkbox, true)
        |> expect(to_be_checked(checkbox))
        |> set_checked(checkbox, true)
        |> expect(to_be_checked(checkbox))
        |> set_checked(checkbox, false)
        |> expect(not_(to_be_checked(checkbox)))
        |> set_checked(checkbox, false)
        |> expect(not_(to_be_checked(checkbox)))
      end)
    end

    @tag driver: driver
    test "set_checked reports the action it performs with #{driver}" do
      html = ~s(<label><input type="radio" name="contact" checked>Email</label>)

      with_html(unquote(driver), html, fn session ->
        error =
          assert_raise Fluffy.OperationError, fn ->
            set_checked(session, by_role(:radio, name: "Email"), false, timeout: 100)
          end

        assert error.operation == :uncheck
      end)
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "clear and set_checked reach LiveView change events with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/live/potions")
      |> fill(by_label("First ingredient"), "ash")
      |> expect(to_be_visible(by_text("Last first: ash")))
      |> clear(by_label("First ingredient"))
      |> expect(to_be_visible(by_text("Last first:", exact: true)))
      |> expect(to_have_value(by_label("First ingredient"), ""))
      |> set_checked(by_label("Enabled"), true)
      |> expect(to_be_checked(by_label("Enabled")))
      |> set_checked(by_label("Enabled"), false)
      |> expect(not_(to_be_checked(by_label("Enabled"))))
    end
  end

  test "LiveView retries clear until a disabled field is enabled and reports it by name" do
    session = :phoenix |> start_test_session() |> visit("/live/potions")
    session = click(session, by_role(:button, name: "Disable first ingredient"))

    error = assert_raise Fluffy.OperationError, fn -> clear(session, by_label("First ingredient"), timeout: 50) end
    assert error.operation == :clear
    assert error.cause.action == :clear
    assert error.cause.reason == :disabled
  end

  for driver <- [:static, :live] do
    @tag driver: driver
    test "clear and set_checked raise a capability error for Playwright options with #{driver}" do
      session = phoenix_page(unquote(driver))
      field = by_label("First ingredient")

      error =
        assert_raise Fluffy.CapabilityError, ~r/:force is a Playwright option/, fn ->
          clear(session, field, force: true)
        end

      assert error.capability == :playwright_action_options

      assert_raise Fluffy.CapabilityError, ~r/:trial is a Playwright option/, fn ->
        set_checked(session, by_label("Enabled"), true, trial: true)
      end
    end
  end

  test "set_checked requires a boolean" do
    session = session_for_html(:static, ~s(<label><input type="checkbox">Updates</label>))
    assert_raise FunctionClauseError, fn -> apply(Fluffy, :set_checked, [session, by_css("input"), :yes]) end
  end

  @tag driver: :playwright
  test "Playwright-only options pass through to clear and set_checked" do
    html = ~s(<input aria-label="Name" value="Ron"><label><input type="checkbox">Updates</label>)
    checkbox = by_role(:checkbox, name: "Updates")

    with_html(:playwright, html, fn session ->
      session
      |> clear(by_label("Name"), force: true)
      |> expect(to_have_value(by_label("Name"), ""))
      |> set_checked(checkbox, true, trial: true)
      |> expect(not_(to_be_checked(checkbox)))
      |> set_checked(checkbox, true, force: true)
      |> expect(to_be_checked(checkbox))
    end)
  end

  defp with_html(driver, html, fun), do: fun.(session_for_html(driver, html, base_url: Fluffy.TestServer.base_url()))

  defp start_test_session(driver),
    do: start_session(driver, base_url: Fluffy.TestServer.base_url(), endpoint: Fluffy.TestWeb.Endpoint)

  defp phoenix_page(:live), do: :phoenix |> start_test_session() |> visit("/live/potions")

  defp phoenix_page(:static) do
    html = ~s(<input aria-label="First ingredient"><label><input type="checkbox">Enabled</label>)
    session_for_html(:static, html)
  end
end
