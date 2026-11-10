defmodule Fluffy.Driver.Live.Click do
  @moduledoc false

  import Phoenix.LiveViewTest

  alias Fluffy.Driver.Live.ActionScope
  alias Fluffy.Driver.Live.Event

  # Mirrors the LiveView client's data-phx-link handling, which takes the click
  # before any phx-click binding sees it.
  def render(view, client_dom, target) do
    case {attribute(target, "data-phx-link"), attribute(target, "href")} do
      {"patch", href} when is_binary(href) ->
        view |> render_patch(href) |> ActionScope.delivered()

      {"redirect", href} when is_binary(href) ->
        kind = if attribute(target, "data-phx-link-state") == "replace", do: :replace, else: :push
        {:error, {:live_redirect, %{to: href, kind: kind}}}

      _not_a_live_link ->
        Event.push(view, target, :click, Event.element_values(client_dom, target))
    end
  end

  defp attribute(target, key), do: target.attributes |> List.keyfind(key, 0, {key, nil}) |> elem(1)
end
