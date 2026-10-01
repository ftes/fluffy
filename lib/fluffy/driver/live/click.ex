defmodule Fluffy.Driver.Live.Click do
  @moduledoc false

  import Phoenix.LiveViewTest

  alias Fluffy.ClientDOM
  alias Fluffy.HTML.Semantics
  alias Fluffy.Locator

  def render(view, client_dom, target, selector) do
    declaration = attribute(target, "phx-click")

    if Semantics.input_type(target) in ["checkbox", "radio"] and declaration do
      payload = checkable_payload(client_dom, target)

      declaration
      |> commands()
      |> Enum.reduce_while(render(view), fn command, result ->
        case dispatch(command, view, target, payload) do
          nil -> {:cont, result}
          {:error, _redirect} = redirect -> {:halt, redirect}
          html -> {:cont, html}
        end
      end)
    else
      view |> element(selector) |> render_click()
    end
  end

  # LiveViewTest's element click reads the server-rendered value attribute. The
  # browser instead uses current checkedness, omitting value when unchecked.
  # Dispatch the complete payload to avoid reintroducing the stale DOM value.
  defp checkable_payload(client_dom, target) do
    payload = for {"phx-value-" <> key, value} <- target.attributes, into: %{}, do: {key, value}

    if ClientDOM.checked?(client_dom, Locator.new({:css, target.selector})) do
      Map.put(payload, "value", attribute(target, "value") || "on")
    else
      Map.delete(payload, "value")
    end
  end

  defp commands("[" <> _ = encoded), do: Phoenix.json_library().decode!(encoded)
  defp commands(event), do: [["push", %{"event" => event}]]

  defp dispatch(["push", %{"event" => event} = options], view, target, payload) do
    view
    |> with_target(options["target"] || attribute(target, "phx-target"))
    |> render_click(event, Map.merge(payload, options["value"] || %{}))
  end

  defp dispatch(["patch", %{"href" => href}], view, _target, _payload), do: render_patch(view, href)

  defp dispatch(["navigate", %{"href" => href} = options], _view, _target, _payload) do
    {:error, {:live_redirect, %{to: href, kind: if(options["replace"], do: :replace, else: :push)}}}
  end

  defp dispatch(_command, _view, _target, _payload), do: nil

  defp attribute(target, key), do: target.attributes |> List.keyfind(key, 0, {key, nil}) |> elem(1)
end
