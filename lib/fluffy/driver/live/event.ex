defmodule Fluffy.Driver.Live.Event do
  @moduledoc false

  # Pushes a binding's event straight to its owning view, as the LiveView
  # client does. LiveViewTest's element/2 finds elements only inside the
  # LiveView container, while the browser also routes bindings in the root
  # layout (to the main view) and in teleported portal content (to the view
  # that owns the portal); its events also send server-rendered values.

  import Fluffy.HTML.Semantics, only: [attribute: 2]
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

      commands = kind == :click && live_link(attributes) ->
        exec(view, commands, attributes, kind, payload)

      declaration = Enum.find_value(names, &attribute(attributes, &1)) ->
        exec(view, commands(declaration), attributes, kind, payload)

      true ->
        raise ArgumentError,
              "element selected by #{inspect(target.selector)} does not have #{Enum.join(names, " or ")}"
    end
  end

  # Like the LiveView client, a LiveView link takes the click before any
  # phx-click binding sees it.
  defp live_link(attributes) do
    case {attribute(attributes, "data-phx-link"), attribute(attributes, "href")} do
      {"patch", href} when is_binary(href) ->
        [["patch", %{"href" => href}]]

      {"redirect", href} when is_binary(href) ->
        [["navigate", %{"href" => href, "replace" => attribute(attributes, "data-phx-link-state") == "replace"}]]

      _not_a_live_link ->
        nil
    end
  end

  # Each command that reaches the view records its delivery, so a later
  # command that finds the view gone does not undo the earlier ones. Only
  # commands that send the view nothing, such as JS.show, need a render.
  defp exec(view, commands, attributes, kind, payload) do
    commands
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
  # phx-value-value. Elements other than form controls, options and list
  # items send only their phx-value-*, as a div or a link does.
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
    do: {:ok, attribute(target.attributes, "value") || target |> Semantics.text() |> Semantics.collapse_whitespace()}

  defp value_property(_client_dom, %{tag: "li"} = target), do: {:ok, integer(attribute(target.attributes, "value"))}
  defp value_property(_client_dom, _target), do: :none

  # HTML's rules for parsing integers, as `li.value` reflects its attribute.
  defp integer(nil), do: 0

  defp integer(value) do
    case value |> String.trim_leading() |> Integer.parse() do
      {integer, _rest} -> integer
      :error -> 0
    end
  end

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
end
