defmodule Fluffy.Driver.Live.Event do
  @moduledoc false

  # Pushes a binding's event straight to its owning view, as the LiveView
  # client does. LiveViewTest's element/2 finds elements only inside the
  # LiveView container, while the browser also routes bindings in the root
  # layout (to the main view) and in teleported portal content (to the view
  # that owns the portal); its events also send server-rendered values.

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

  # A disabled control or an element without the binding gets no event in the
  # browser. These raise, as LiveViewTest's element events do, so a test does
  # not pass without noticing.
  def push(view, %{attributes: attributes} = target, kind, payload) do
    names = Map.fetch!(@bindings, kind)

    cond do
      disabled?(target) ->
        raise ArgumentError, "cannot #{kind} element #{inspect(target.selector)} because it is disabled"

      declaration = Enum.find_value(names, &attribute(attributes, &1)) ->
        exec(view, declaration, attributes, kind, payload)

      true ->
        raise ArgumentError,
              "element selected by #{inspect(target.selector)} does not have #{Enum.join(names, " or ")}"
    end
  end

  # Each command that reaches the view records its delivery, so a later
  # command that finds the view gone does not undo the earlier ones. Only
  # commands that send the view nothing, such as JS.show, need a render.
  def exec(view, declaration, attributes, kind, payload) do
    declaration
    |> commands()
    |> Enum.reduce_while(:none, fn command, result ->
      case dispatch(command, view, attributes, kind, payload) do
        :skip -> {:cont, result}
        {:error, _redirect} = redirect -> {:halt, redirect}
        nil when result != :none -> {:cont, result}
        html -> {:cont, html}
      end
    end)
    |> then(fn
      :none -> render(view)
      result -> result
    end)
  end

  # Click and key events carry the element's phx-value-* attributes, while
  # form events carry the serialized form and the form's phx-value-*.
  def values(attributes) do
    for {"phx-value-" <> key, value} <- attributes, into: %{}, do: {key, value}
  end

  # Like the LiveView client's extractMeta, a click or key event also carries
  # the element's `value` property, where it has one: a form control's current
  # value, where LiveViewTest sends the server-rendered attribute and misses a
  # fill. An unchecked checkbox or radio sends no value, not even its
  # phx-value-value. An element without the property, such as a div or a link,
  # sends only its phx-value-*.
  def element_values(client_dom, %{attributes: attributes} = target) do
    case value_property(client_dom, target) do
      :none -> values(attributes)
      :unchecked -> attributes |> values() |> Map.delete("value")
      {:ok, value} -> attributes |> values() |> Map.put("value", value)
    end
  end

  defp value_property(client_dom, %{tag: tag, attributes: attributes} = target)
       when tag in ["button", "input", "select", "textarea"] do
    locator = Locator.by_css(target.selector)

    cond do
      Semantics.input_type(target) not in ["checkbox", "radio"] -> {:ok, ClientDOM.value(client_dom, locator)}
      ClientDOM.checked?(client_dom, locator) -> {:ok, attribute(attributes, "value") || "on"}
      true -> :unchecked
    end
  end

  defp value_property(_client_dom, %{tag: "option"} = target),
    do: {:ok, attribute(target.attributes, "value") || target.children |> text() |> normalize()}

  defp value_property(_client_dom, %{tag: tag} = target) when tag in ["data", "param"],
    do: {:ok, attribute(target.attributes, "value") || ""}

  defp value_property(_client_dom, %{tag: "output"} = target), do: {:ok, text(target.children)}
  defp value_property(_client_dom, %{tag: "li"} = target), do: {:ok, integer(attribute(target.attributes, "value"))}

  defp value_property(_client_dom, %{tag: "meter", attributes: attributes}) do
    min = number(attribute(attributes, "min")) || 0
    max = max(number(attribute(attributes, "max")) || 1, min)
    {:ok, attributes |> attribute("value") |> number() |> Kernel.||(0) |> max(min) |> min(max) |> js_number()}
  end

  defp value_property(_client_dom, %{tag: "progress", attributes: attributes}) do
    max = attributes |> attribute("max") |> number()
    max = if max && max > 0, do: max, else: 1
    {:ok, attributes |> attribute("value") |> number() |> Kernel.||(0) |> max(0) |> min(max) |> js_number()}
  end

  defp value_property(_client_dom, _target), do: :none

  defp text(nil), do: ""
  defp text(nodes) when is_list(nodes), do: Enum.map_join(nodes, &text/1)
  defp text({_tag, _attributes, children}), do: text(children)
  defp text(text) when is_binary(text), do: text
  defp text(_comment), do: ""

  defp normalize(text), do: text |> String.split(~r/[\t\n\f\r ]+/, trim: true) |> Enum.join(" ")

  # HTML's rules for parsing integers, as `li.value` reflects its attribute.
  defp integer(nil), do: 0

  defp integer(value) do
    case value |> String.trim_leading() |> Integer.parse() do
      {integer, _rest} -> integer
      :error -> 0
    end
  end

  defp number(nil), do: nil

  defp number(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _invalid -> nil
    end
  end

  # JSON sends an integral JavaScript number as an integer.
  defp js_number(number) when number == trunc(number), do: trunc(number)
  defp js_number(number), do: number

  defp disabled?(%{tag: tag} = target) when tag in ["button", "input", "select", "textarea"],
    do: target.disabled? or List.keymember?(target.attributes, "disabled", 0)

  defp disabled?(_target), do: false

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

  defp dispatch(_command, _view, _attributes, _kind, _payload), do: :skip

  defp attribute(attributes, name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end
end
