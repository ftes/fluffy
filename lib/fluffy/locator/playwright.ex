defmodule Fluffy.Locator.Playwright do
  @moduledoc false
  # Builds a PlaywrightEx locator from a `Fluffy.Locator`, one call per operation; it never writes selector strings.

  alias Fluffy.Locator
  alias Fluffy.Locator.Internal
  alias PlaywrightEx.FrameLocator
  alias PlaywrightEx.Isomorphic.LocatorUtils
  alias PlaywrightEx.Isomorphic.SelectorParser
  alias PlaywrightEx.Locator, as: Native

  # Nested locators (`has:`, `and_/2`, `or_/2`, `within/2`) are built from `frame` too, as
  # PlaywrightEx requires them to belong to the same frame.
  def locator(frame, %Locator{} = locator) do
    locator.operations
    |> Enum.reduce({:root, frame}, &apply_operation(frame, &1, &2))
    |> native()
  end

  defp apply_operation(_frame, :enter_frame, scope), do: scope |> native() |> Native.content_frame()

  # Forces the CSS engine, as upstream's `stringifySelector(…, forceEngineName)` does, since a
  # bare selector could also be XPath or another engine.
  defp apply_operation(_frame, {:css, css}, scope) do
    selector = SelectorParser.stringify_selector(%{parts: [%{name: "css", body: css, source: css}]}, true)
    call(scope, :locator, [selector])
  end

  # `get_by_role` takes only the roles of Playwright's `AriaRole` type, which lacks some that
  # the browser matches, such as `mark`. PlaywrightEx's selector builder takes any role.
  defp apply_operation(_frame, {:role, role, options}, scope) do
    options =
      Map.new(options, fn
        {:include_hidden, include_hidden} -> {:includeHidden, include_hidden}
        option -> option
      end)

    call(scope, :locator, [LocatorUtils.get_by_role_selector(role, options)])
  end

  defp apply_operation(_frame, {:text, text, options}, scope), do: call(scope, :get_by_text, [text, options])
  defp apply_operation(_frame, {:label, text, options}, scope), do: call(scope, :get_by_label, [text, options])

  defp apply_operation(_frame, {:attribute, "placeholder", text, options}, scope),
    do: call(scope, :get_by_placeholder, [text, options])

  defp apply_operation(_frame, {:attribute, "alt", text, options}, scope),
    do: call(scope, :get_by_alt_text, [text, options])

  defp apply_operation(_frame, {:attribute, "title", text, options}, scope),
    do: call(scope, :get_by_title, [text, options])

  # `get_by_test_id` reads one attribute for all locators (`set_test_id_attribute`), while
  # `by_test_id(attribute:)` picks it per locator, so this passes it to PlaywrightEx's builder.
  defp apply_operation(_frame, {:test_id, attribute_name, test_id}, scope),
    do: call(scope, :locator, [LocatorUtils.get_by_test_id_selector(attribute_name, test_id)])

  defp apply_operation(frame, {:and, right}, scope), do: scope |> native() |> Native.and_(locator(frame, right))
  defp apply_operation(frame, {:or, right}, scope), do: scope |> native() |> Native.or_(locator(frame, right))

  # A chained selector cannot enter a frame; only a parent starting the selector is not chained.
  defp apply_operation(frame, {:within, parent, child}, scope) do
    if Internal.crosses_frame?(child) or (not root?(scope) and Internal.crosses_frame?(parent)) do
      raise ArgumentError,
            "within/2 cannot enter a frame inside a chained locator, got: " <>
              "within(#{Internal.describe(child)}, #{Internal.describe(parent)}); " <>
              "start the locator from the frame instead"
    end

    parent = if root?(scope), do: locator(frame, parent), else: call(scope, :locator, [locator(frame, parent)])
    Native.within(locator(frame, child), parent)
  end

  # One `filter` per option keeps the options in the caller's order.
  defp apply_operation(frame, {:filter, options}, scope) do
    Enum.reduce(options, native(scope), fn
      {key, %Locator{} = child}, current -> Native.filter(current, [{key, locator(frame, child)}])
      option, current -> Native.filter(current, [option])
    end)
  end

  defp apply_operation(_frame, {:nth, index}, scope), do: scope |> native() |> Native.nth(index)

  defp call({:root, frame}, function, arguments), do: apply(PlaywrightEx.Frame, function, [frame | arguments])
  defp call(%FrameLocator{} = scope, function, arguments), do: apply(FrameLocator, function, [scope | arguments])
  defp call(%Native{} = scope, function, arguments), do: apply(Native, function, [scope | arguments])

  defp root?(scope), do: match?({:root, _frame}, scope)

  # The public API starts every locator, and every frame scope, with a `by_*` locator.
  defp native(%Native{} = native), do: native

  defp native(_scope), do: raise(ArgumentError, "a locator and a frame scope must start from a by_* locator")
end
