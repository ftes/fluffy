defmodule Fluffy.Driver.Live.Event do
  @moduledoc false

  # Pushes a binding's event straight to its owning view. LiveViewTest's
  # element/2 only finds elements inside the LiveView container, while the
  # browser also routes bindings in the root layout (to the main view) and in
  # teleported portal content (to the view that owns the portal).

  import Phoenix.LiveViewTest

  alias Fluffy.ClientDOM
  alias Fluffy.Driver.Live.ActionScope
  alias Fluffy.HTML.Semantics
  alias Fluffy.Locator

  @bindings %{
    click: ["phx-click"],
    change: ["phx-change"],
    submit: ["phx-submit"],
    keydown: ["phx-keydown", "phx-window-keydown"],
    keyup: ["phx-keyup", "phx-window-keyup"]
  }

  def push(view, %{attributes: attributes}, kind, payload) do
    case Enum.find_value(Map.fetch!(@bindings, kind), &attribute(attributes, &1)) do
      nil -> render(view)
      declaration -> exec(view, declaration, attributes, kind, payload)
    end
  end

  # Each command that reaches the view records its delivery, so a later
  # command that finds the view gone does not undo the earlier ones.
  def exec(view, declaration, attributes, kind, payload) do
    declaration
    |> commands()
    |> Enum.reduce_while(render(view), fn command, result ->
      case dispatch(command, view, attributes, kind, payload) do
        nil -> {:cont, result}
        {:error, _redirect} = redirect -> {:halt, redirect}
        html -> {:cont, html}
      end
    end)
  end

  # Click and key events carry the element's phx-value-* attributes, while
  # form events carry the serialized form and the form's phx-value-*.
  def values(attributes) do
    for {"phx-value-" <> key, value} <- attributes, into: %{}, do: {key, value}
  end

  # Like the LiveView client's extractMeta, a click or key event also carries
  # a form control's current value, where LiveViewTest sends the
  # server-rendered attribute and misses a fill. An unchecked checkbox or radio
  # sends no value, not even its phx-value-value. Other elements send their
  # value attribute, as LiveViewTest does.
  def element_values(client_dom, %{tag: tag, attributes: attributes} = target)
      when tag in ["button", "input", "select", "textarea"] do
    locator = Locator.by_css(target.selector)

    cond do
      Semantics.input_type(target) not in ["checkbox", "radio"] ->
        Map.put(values(attributes), "value", ClientDOM.value(client_dom, locator))

      ClientDOM.checked?(client_dom, locator) ->
        Map.put(values(attributes), "value", attribute(attributes, "value") || "on")

      true ->
        attributes |> values() |> Map.delete("value")
    end
  end

  def element_values(_client_dom, %{attributes: attributes}) do
    case attribute(attributes, "value") do
      nil -> values(attributes)
      value -> attributes |> values() |> Map.put("value", value)
    end
  end

  defp commands("[" <> _ = encoded), do: Phoenix.json_library().decode!(encoded)
  defp commands(event), do: [["push", %{"event" => event}]]

  # As in the LiveView client's exec_push, a push's own target replaces the
  # element's phx-target, where LiveViewTest's element events send to both.
  defp dispatch(["push", %{"event" => event} = options], view, attributes, kind, payload) do
    view = with_target(view, options["target"] || attribute(attributes, "phx-target"))
    value = Map.merge(payload, options["value"] || %{})

    result =
      case kind do
        :click -> render_click(view, event, value)
        :change -> render_change(view, event, value)
        :submit -> render_submit(view, event, value)
        :keydown -> render_keydown(view, event, value)
        :keyup -> render_keyup(view, event, value)
      end

    ActionScope.delivered(result)
  end

  defp dispatch(["patch", %{"href" => href}], view, _attributes, _kind, _payload),
    do: view |> render_patch(href) |> ActionScope.delivered()

  defp dispatch(["navigate", %{"href" => href} = options], _view, _attributes, _kind, _payload) do
    {:error, {:live_redirect, %{to: href, kind: if(options["replace"], do: :replace, else: :push)}}}
  end

  defp dispatch(_command, _view, _attributes, _kind, _payload), do: nil

  defp attribute(attributes, name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end
end
