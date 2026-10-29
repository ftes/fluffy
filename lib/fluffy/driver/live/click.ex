defmodule Fluffy.Driver.Live.Click do
  @moduledoc false

  import Phoenix.LiveViewTest

  alias Fluffy.ClientDOM
  alias Fluffy.Driver.Live.Event
  alias Fluffy.HTML.Semantics
  alias Fluffy.Locator

  # A nil selector means the target is outside the view's container, so
  # LiveViewTest's element/2 cannot reach it.
  def render(view, client_dom, target, selector) do
    declaration = attribute(target, "phx-click")

    cond do
      Semantics.input_type(target) in ["checkbox", "radio"] and declaration ->
        Event.exec(view, declaration, target.attributes, :click, checkable_payload(client_dom, target))

      is_nil(selector) ->
        render_detached(view, target, declaration)

      true ->
        view |> element(selector) |> render_click()
    end
  end

  # Mirrors the LiveView client's data-phx-link handling, which applies to
  # links anywhere in the document through the main view.
  defp render_detached(view, target, declaration) do
    case {attribute(target, "data-phx-link"), attribute(target, "href")} do
      {"patch", href} when is_binary(href) ->
        render_patch(view, href)

      {"redirect", href} when is_binary(href) ->
        kind = if attribute(target, "data-phx-link-state") == "replace", do: :replace, else: :push
        {:error, {:live_redirect, %{to: href, kind: kind}}}

      _not_a_live_link ->
        Event.exec(view, declaration, target.attributes, :click, click_payload(target))
    end
  end

  defp click_payload(target) do
    case attribute(target, "value") do
      nil -> Event.values(target.attributes)
      value -> Map.put_new(Event.values(target.attributes), "value", value)
    end
  end

  # LiveViewTest's element click reads the server-rendered value attribute. The
  # browser instead uses current checkedness, omitting value when unchecked.
  # Dispatch the complete payload to avoid reintroducing the stale DOM value.
  defp checkable_payload(client_dom, target) do
    payload = Event.values(target.attributes)

    if ClientDOM.checked?(client_dom, Locator.new({:css, target.selector})) do
      Map.put(payload, "value", attribute(target, "value") || "on")
    else
      Map.delete(payload, "value")
    end
  end

  defp attribute(target, key), do: target.attributes |> List.keyfind(key, 0, {key, nil}) |> elem(1)
end
