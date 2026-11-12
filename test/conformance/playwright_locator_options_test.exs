defmodule Fluffy.Conformance.PlaywrightLocatorOptionsTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestWeb.Endpoint

  @states """
  <button aria-pressed="true">Bold</button>
  <button aria-pressed="false">Italic</button>
  <button disabled>Locked</button>
  <button aria-expanded="true">Menu</button>
  <button hidden>Ghost</button>
  <button aria-describedby="hint">Send</button><p id="hint">Sends the draft</p>
  <label><input type="checkbox" checked> Agree</label>
  <label><input type="checkbox"> Spam</label>
  <h2>Section</h2><h3>Subsection</h3>
  <div role="listbox" aria-label="Sizes">
    <div role="option" aria-selected="true">Small</div>
    <div role="option" aria-selected="false">Large</div>
  </div>
  """

  @text """
  <ul><li>Apple pie</li><li>Apple tart</li><li>Banana bread</li></ul>
  """

  @tag driver: :playwright
  test "role states compile into the Playwright role selector" do
    :playwright
    |> session_for_html(@states, base_url: Fluffy.TestServer.base_url())
    |> expect(to_have_count(by_role(:button, pressed: true), 1))
    |> expect(to_have_count(by_role(:button, name: "Bold", pressed: false), 0))
    |> expect(to_have_count(by_role(:button, name: "Locked", disabled: true), 1))
    |> expect(to_have_count(by_role(:button, name: "Bold", disabled: true), 0))
    |> expect(to_have_count(by_role(:button, expanded: true), 1))
    |> expect(to_have_count(by_role(:checkbox, checked: true), 1))
    |> expect(to_have_count(by_role(:checkbox, name: "Spam", checked: false), 1))
    |> expect(to_have_count(by_role(:heading, level: 2), 1))
    |> expect(to_have_count(by_role(:option, selected: true), 1))
    |> expect(to_have_count(by_role(:button, name: "Ghost"), 0))
    |> expect(to_have_count(by_role(:button, name: "Ghost", include_hidden: true), 1))
    |> expect(to_have_count(by_role(:button, description: "sends the"), 1))
    |> expect(to_have_count(by_role(:button, description: "sends the", exact: true), 0))
    |> expect(to_have_count(by_role(:button, description: ~r/^Sends/), 1))
    |> expect(to_be_visible(by_role(:option, name: "Small", selected: true)))
  end

  test "Playwright-only options are validated when the locator is built" do
    assert_raise NimbleOptions.ValidationError, ~r/:pressed/, fn -> by_role(:button, pressed: "yes") end
    assert_raise NimbleOptions.ValidationError, ~r/:level/, fn -> by_role(:heading, level: "2") end
    assert_raise NimbleOptions.ValidationError, ~r/:has_text/, fn -> filter(by_css("li"), has_text: 1) end

    # Text options take a string, a Regex or a PlaywrightEx.RegExp; a Regex becomes a RegExp.
    for {key, locator} <- [description: &by_role(:button, description: &1), name: &by_role(:button, name: &1)] do
      assert_raise NimbleOptions.ValidationError, ~r/#{key}/, fn -> locator.(:x) end
      assert locator.(~r/x/i) == locator.(PlaywrightEx.RegExp.new("x", "i"))
    end

    assert inspect(by_role(:button, name: ~r/x/, pressed: true)) ==
             "#Fluffy.Locator<by_role(:button, name: #PlaywrightEx.RegExp</x/>, pressed: true)>"
  end

  for driver <- [:static, :live] do
    @tag driver: driver
    test "Playwright-only locator options raise a capability error when resolved with #{driver}" do
      session = session(unquote(driver))

      # Building and composing the locators does not raise.
      pressed = by_role(:button, pressed: true)
      nested = "ul" |> by_css() |> filter(has: by_role(:listitem, level: 1)) |> and_(by_css("ul"))

      for {operation, message} <- [
            {fn -> click(session, pressed) end, ~r/:pressed is a Playwright locator option/},
            {fn -> expect(session, "p" |> by_css() |> or_(nested) |> to_be_visible()) end, ~r/:level/}
          ] do
        error = assert_raise Fluffy.CapabilityError, message, operation
        assert error.capability == :playwright_locator_options
        assert error.driver == unquote(driver)
      end
    end
  end

  defp session(:static), do: session_for_html(:static, @text)
  defp session(:live), do: :phoenix |> start_session(endpoint: Endpoint) |> visit("/live/nested")
end
