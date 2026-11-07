defmodule Fluffy.Conformance.NativeOptionsTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Options
  alias Fluffy.Options.NativeGenerated
  alias Fluffy.TestWeb.Endpoint
  alias Mix.Tasks.Fluffy.Gen.NativeOptions

  @button ~s(<button onclick="this.textContent = event.shiftKey ? 'shift' : 'plain'">Cast</button>)
  @states ~s(<button disabled>Locked</button><input aria-label="Sealed" readonly><p hidden>Secret</p>)

  # Compares data, not source, so older Elixir formatters agree; CI also runs `--check`.
  test "the generated upstream options are fresh" do
    for {module, fun, arity} <- NativeOptions.calls() do
      assert normalize(NativeGenerated.options(module, fun, arity)) ==
               normalize(NativeOptions.options(module, fun, arity)),
             "run `mix fluffy.gen.native_options` (#{inspect(module)}.#{fun}/#{arity} is stale)"
    end
  end

  # Classification reads the installed PlaywrightEx's `__options__/1`, not the generated file.
  test "every upstream option of an action is classified" do
    for {action, {module, fun, _arity, playwright}} <- Options.native_actions() ++ Options.playwright_actions() do
      fluffy = Options.fluffy_native_keys() ++ Options.denied_native_keys()

      assert Enum.sort(upstream_keys(module, fun) -- fluffy) == Enum.sort(playwright),
             "classify the upstream options of #{inspect(action)} in Fluffy.Options"
    end
  end

  test "every upstream option of an expectation is classified" do
    for {matcher, {module, fun, _arity, mirrored}} <- Options.native_expectations() do
      classified = Options.fluffy_native_keys() ++ Options.denied_expectation_keys() ++ mirrored

      assert Enum.sort(upstream_keys(module, fun)) == Enum.sort(classified),
             "classify the upstream options of #{inspect(matcher)} in Fluffy.Options"
    end
  end

  # Page, Frame and FrameLocator factories take the options of their Locator counterpart.
  test "every upstream option of a locator is classified" do
    for {locator, {module, fun, _arity, classes}} <- Options.native_locators() do
      classified = classes |> Keyword.values() |> List.flatten()

      for factory <- [module, PlaywrightEx.Page, PlaywrightEx.Frame, PlaywrightEx.FrameLocator],
          Keyword.has_key?(factory.__info__(:functions), fun) do
        assert Enum.sort(locator_keys(factory, fun)) == Enum.sort(classified),
               "classify the upstream options of #{inspect(factory)}.#{fun} for #{inspect(locator)} in Fluffy.Options"
      end

      accepted = locator |> locator_schema() |> Map.fetch!(:schema) |> Keyword.keys()
      supported = Keyword.get(classes, :fluffy, []) ++ Keyword.get(classes, :playwright, [])

      assert supported -- accepted == [], "#{inspect(locator)} must accept its Fluffy-owned and Playwright options"

      assert Enum.filter(Keyword.get(classes, :denied, []), &(&1 in accepted)) == [],
             "#{inspect(locator)} accepts a denied option"
    end
  end

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "state flags and ignore_case mirror Playwright with #{driver}" do
      unquote(driver)
      |> session_for_html(@states, base_url: Fluffy.TestServer.base_url())
      |> expect(to_be_enabled(by_role(:button, name: "Locked"), enabled: false))
      |> expect(to_be_editable(by_label("Sealed"), editable: false))
      |> expect(to_be_visible(by_text("Secret"), visible: false))
      |> expect(not_(to_be_visible(by_role(:button, name: "Locked"), visible: false)))

      unquote(driver)
      |> visited_session("/stage")
      |> expect(page_to_have_url("/STAGE", ignore_case: true))
      |> expect(page_to_have_url(~r/STAGE$/, ignore_case: true))
      |> expect(not_(page_to_have_url(~r/STAGE$/i, ignore_case: false)))
    end
  end

  for driver <- [:static, :live, :playwright] do
    @tag driver: driver
    test "ignore_case: false leaves a predicate or structured URL unchanged with #{driver}" do
      path = if unquote(driver) == :live, do: "/live/nested", else: "/stage"

      unquote(driver)
      |> visited_session(path)
      |> expect(page_to_have_url(&(&1.path == path), ignore_case: false))
      |> expect(page_to_have_url([path: path], ignore_case: false))
    end
  end

  test "ignore_case requires a string or regular expression URL" do
    assert_raise ArgumentError, ~r/ignore_case: requires/, fn -> page_to_have_url([path: "/"], ignore_case: true) end

    assert_raise ArgumentError, ~r/ignore_case: requires/, fn ->
      page_to_have_url(&(&1.path == "/"), ignore_case: true)
    end
  end

  @tag driver: :playwright
  test "Playwright-only options pass through to the browser" do
    with_session(:playwright, fn session ->
      session
      |> click(by_role(:button, name: "Cast"), trial: true)
      |> expect(to_be_visible(by_role(:button, name: "Cast")))
      |> click(by_role(:button, name: "Cast"), modifiers: [:shift])
      |> expect(to_be_visible(by_role(:button, name: "shift")))
    end)
  end

  for driver <- [:static, :live] do
    @tag driver: driver
    test "Playwright-only options raise a capability error with #{driver}" do
      with_session(unquote(driver), fn session ->
        error =
          assert_raise Fluffy.CapabilityError, ~r/:force is a Playwright option/, fn ->
            click(session, by_role(:button, name: "Cast"), force: true)
          end

        assert error.capability == :playwright_action_options
        assert Fluffy.Capability.status(error.capability, unquote(driver)) == :browser_only
      end)
    end
  end

  test "options that bypass navigation tracking are rejected" do
    with_session(:static, fn session ->
      assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:no_wait_after/, fn ->
        click(session, by_role(:button, name: "Cast"), no_wait_after: true)
      end
    end)
  end

  @tag driver: :playwright
  test "Playwright-only actions reject options that bypass navigation tracking" do
    with_session(:playwright, fn session ->
      button = by_role(:button, name: "Cast")

      for call <- [
            &Fluffy.Playwright.hover(session, button, &1),
            &Fluffy.Playwright.drag_to(session, button, button, &1),
            &Fluffy.Playwright.press_sequentially(session, button, "x", &1),
            &Fluffy.Playwright.focus(session, button, &1),
            &Fluffy.Playwright.blur(session, button, &1),
            &Fluffy.Playwright.go_back(session, &1),
            &Fluffy.Playwright.go_forward(session, &1),
            &Fluffy.Playwright.install_clock(session, &1)
          ],
          option <- [no_wait_after: true, signal: nil, timeout: :infinity] do
        assert_raise NimbleOptions.ValidationError, fn -> call.([option]) end
      end
    end)
  end

  defp normalize(options),
    do: for({key, {type_doc, doc, spec}} <- options, do: {key, type_doc, doc, Macro.to_string(spec)})

  defp upstream_keys(module, fun), do: fun |> module.__options__() |> Keyword.keys()

  # `__options__/1` has no clause for a factory without options.
  defp locator_keys(module, fun) do
    upstream_keys(module, fun)
  rescue
    FunctionClauseError -> []
  end

  defp locator_schema(:by_role), do: Options.role_locator_schema()
  defp locator_schema(:by_test_id), do: Options.test_id_locator_schema()
  defp locator_schema(:filter), do: Options.filter_locator_schema()
  defp locator_schema(:by_css), do: NimbleOptions.new!([])
  defp locator_schema(_text_locator), do: Options.exact_locator_schema()

  defp visited_session(driver, path) when driver in [:static, :live],
    do: :phoenix |> start_session(endpoint: Endpoint) |> visit(path)

  defp visited_session(:playwright, path),
    do: :playwright |> start_session(base_url: Fluffy.TestServer.base_url()) |> visit(path)

  # Options are validated before the target is resolved.
  defp with_session(:live, fun) do
    :phoenix |> start_session(endpoint: Endpoint) |> visit("/live/nested") |> fun.()
  end

  defp with_session(driver, fun) do
    fun.(session_for_html(driver, @button, base_url: Fluffy.TestServer.base_url()))
  end
end
