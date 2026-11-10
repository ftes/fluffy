defmodule Fluffy.Driver.Live.Click do
  @moduledoc false

  import Phoenix.LiveViewTest

  alias Fluffy.Driver.Live.ActionScope
  alias Fluffy.Driver.Live.Event
  alias Fluffy.HTML.Semantics

  # A nil selector means the target is outside the view's container, so
  # LiveViewTest's element/2 cannot reach it.
  def render(view, client_dom, target, selector) do
    declaration = attribute(target, "phx-click")

    cond do
      # LiveViewTest's element click would send an unchecked box's value
      # attribute, and a payload can't remove it.
      Semantics.input_type(target) in ["checkbox", "radio"] and declaration ->
        Event.exec(view, declaration, target.attributes, :click, Event.element_values(client_dom, target))

      is_nil(selector) ->
        render_detached(view, client_dom, target, declaration)

      true ->
        view |> element(selector) |> render_click() |> ActionScope.delivered()
    end
  end

  # Mirrors the LiveView client's data-phx-link handling, which applies to
  # links anywhere in the document through the main view.
  defp render_detached(view, client_dom, target, declaration) do
    case {attribute(target, "data-phx-link"), attribute(target, "href")} do
      {"patch", href} when is_binary(href) ->
        view |> render_patch(href) |> ActionScope.delivered()

      {"redirect", href} when is_binary(href) ->
        kind = if attribute(target, "data-phx-link-state") == "replace", do: :replace, else: :push
        {:error, {:live_redirect, %{to: href, kind: kind}}}

      _not_a_live_link ->
        Event.exec(view, declaration, target.attributes, :click, Event.element_values(client_dom, target))
    end
  end

  defp attribute(target, key), do: target.attributes |> List.keyfind(key, 0, {key, nil}) |> elem(1)
end
