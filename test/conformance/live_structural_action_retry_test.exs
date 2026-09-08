defmodule Fluffy.Conformance.LiveStructuralActionRetryTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  @action_timeout 1_000

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "click waits for a target to appear with #{driver}" do
      unquote(driver)
      |> live_session()
      |> click(by_role(:button, name: "Release appearing button"))
      |> click(by_role(:button, name: "Appearing action"), timeout: @action_timeout)
      |> expect("Appearing result: activated" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "click waits for a disabled fieldset to release its target with #{driver}" do
      unquote(driver)
      |> live_session()
      |> click(by_role(:button, name: "Release fieldset button"))
      |> click(by_role(:button, name: "Fieldset action"), timeout: @action_timeout)
      |> expect("Fieldset result: activated" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "click waits for aria-disabled to clear with #{driver}" do
      unquote(driver)
      |> live_session()
      |> click(by_role(:button, name: "Release ARIA button"))
      |> click(by_role(:button, name: "ARIA action"), timeout: @action_timeout)
      |> expect("ARIA result: activated" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "click waits for hidden to clear with #{driver}" do
      unquote(driver)
      |> live_session()
      |> click(by_role(:button, name: "Release hidden button"))
      |> click(by_css("#hidden-action"), timeout: @action_timeout)
      |> expect("Hidden result: activated" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "fill waits for readonly to clear with #{driver}" do
      unquote(driver)
      |> live_session()
      |> click(by_role(:button, name: "Release readonly field"))
      |> fill(by_label("Name"), "Ada", timeout: @action_timeout)
      |> expect("Name" |> by_label() |> to_have_value("Ada"))
      |> expect("Name result: Ada" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "check waits for disabled to clear with #{driver}" do
      unquote(driver)
      |> live_session()
      |> click(by_role(:button, name: "Release checkbox"))
      |> check(by_label("Updates"), timeout: @action_timeout)
      |> expect("Updates" |> by_label() |> to_be_checked())
      |> expect("Updates result: checked" |> by_text(exact: true) |> to_be_visible())
    end

    @tag driver: driver
    test "select waits for an option added after another field changes with #{driver}" do
      unquote(driver)
      |> live_session()
      |> check(by_label("Reveal Phoenix Tonic"))
      |> select_option(by_label("Potion", exact: true), "pro", timeout: @action_timeout)
      |> expect("Potion" |> by_label(exact: true) |> to_have_value("pro"))
      |> expect("Potion result: pro" |> by_text(exact: true) |> to_be_visible())
    end
  end

  @tag driver: :phoenix
  test "continues a structural action retry after a Live document replacement" do
    :phoenix
    |> live_session()
    |> click(by_role(:button, name: "Release by navigation"))
    |> click(by_css("#retry-across-navigation"), timeout: @action_timeout)
    |> expect("Navigation retry result: activated" |> by_text(exact: true) |> to_be_visible())
  end

  @tag driver: :phoenix
  test "the latest retryable failure is preserved at the action deadline" do
    session = live_session(:phoenix)

    missing = by_css("#never-appears")

    error =
      assert_raise Fluffy.StrictnessError, fn ->
        click(session, missing, timeout: 20)
      end

    assert error.locator == missing
    assert error.candidates == []

    disabled = by_css("#permanently-disabled")

    error =
      assert_raise Fluffy.ActionabilityError, fn ->
        click(session, disabled, timeout: 20)
      end

    assert error.action == :click
    assert error.reason == :disabled
    assert error.locator == disabled

    readonly = by_css("#permanently-readonly")

    error =
      assert_raise Fluffy.ActionabilityError, fn ->
        fill(session, readonly, "Ada", timeout: 20)
      end

    assert error.action == :fill
    assert error.reason == :readonly
    assert error.locator == readonly

    select = by_css("#permanent-plan")

    error =
      assert_raise Fluffy.ActionabilityError, fn ->
        select_option(session, select, "pro", timeout: 20)
      end

    assert error.action == :select_option
    assert error.reason == :option_not_found
    assert error.locator == select
  end

  @tag driver: :phoenix
  test "semantic action errors fail immediately" do
    session = live_session(:phoenix)

    failures = [
      fn -> click(session, by_css(".ambiguous"), timeout: @action_timeout) end,
      fn -> fill(session, by_css("#wrong-fill-target"), "Ada", timeout: @action_timeout) end,
      fn ->
        fill(
          session,
          by_css("#readonly-wrong-fill-target"),
          "Ada",
          timeout: @action_timeout
        )
      end,
      fn -> check(session, by_css("#permanently-readonly"), timeout: @action_timeout) end,
      fn ->
        select_option(session, by_css("#permanently-readonly"), "pro", timeout: @action_timeout)
      end,
      fn ->
        select_option(session, by_css("#permanent-plan"), "disabled", timeout: @action_timeout)
      end
    ]

    started_at = System.monotonic_time(:millisecond)

    assert_raise Fluffy.StrictnessError, Enum.at(failures, 0)

    assert_actionability_error(:not_editable, Enum.at(failures, 1))
    assert_actionability_error(:not_editable, Enum.at(failures, 2))
    assert_actionability_error(:not_checkable, Enum.at(failures, 3))
    assert_actionability_error(:not_selectable, Enum.at(failures, 4))
    assert_actionability_error(:disabled_option, Enum.at(failures, 5))

    assert System.monotonic_time(:millisecond) - started_at < 500
  end

  defp live_session(driver) do
    driver
    |> start_session(
      endpoint: Fluffy.TestWeb.Endpoint,
      base_url: Fluffy.TestServer.base_url()
    )
    |> visit("/live/action-retries")
  end

  defp assert_actionability_error(reason, fun) do
    error = assert_raise Fluffy.ActionabilityError, fun
    assert error.reason == reason
  end
end
