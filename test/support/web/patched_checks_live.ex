defmodule Fluffy.TestWeb.PatchedChecksLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, count: 0, changes: 0, stored: %{}, shown: nil)}

  @impl true
  def handle_event("bump", _params, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
  def handle_event("change", _params, socket), do: {:noreply, update(socket, :changes, &(&1 + 1))}
  def handle_event("noop", _params, socket), do: {:noreply, socket}
  # Stores the params without rendering them, so the change patches nothing.
  def handle_event("store", params, socket), do: {:noreply, assign(socket, :stored, params)}
  def handle_event("show", _params, socket), do: {:noreply, assign(socket, :shown, format(socket.assigns.stored))}

  defp format(params) do
    params
    |> Enum.reject(fn {name, _value} -> String.starts_with?(name, "_") end)
    |> Enum.sort()
    |> Enum.map_join(", ", fn {name, value} -> "#{name}=#{value}" end)
  end

  # The server never renders what the user checks, so a reset shows.
  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <form id="loose">
        <input type="checkbox" name="loose" aria-label="Loose" />
        <input type="radio" name="loose_pick" value="a" aria-label="Loose a" checked />
        <input type="radio" name="loose_pick" value="b" aria-label="Loose b" />
        <input
          id="ignored-box"
          type="checkbox"
          name="ignored"
          aria-label="Ignored"
          phx-update="ignore"
        />
      </form>
      <form id="tracked" phx-change="change">
        <input type="checkbox" name="tracked" aria-label="Tracked" />
        <input type="radio" name="pick" value="a" aria-label="Pick a" checked />
        <input type="radio" name="pick" value="b" aria-label="Pick b" />
      </form>
      <form id="quiet" phx-change="noop">
        <input type="checkbox" name="clicked" aria-label="Clicked" phx-click="bump" />
      </form>
      <form id="stored" phx-change="store">
        <input name="note" aria-label="Stored note" />
        <input type="checkbox" name="other" aria-label="Other box" />
        <input type="checkbox" name="bumped" aria-label="Bumped box" phx-click="bump" />
      </form>
      <button id="show-params" type="button" phx-click="show">Show params</button>
      <p :if={@shown}>Params: {@shown}</p>
      <button type="button" phx-click="bump">Bump</button>
      <p>Count: {@count}</p>
      <p>Changes: {@changes}</p>
    </main>
    """
  end
end
