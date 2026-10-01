defmodule Fluffy.TestWeb.CheckboxPayloadComponent do
  @moduledoc false
  use Phoenix.LiveComponent

  @impl true
  def mount(socket), do: {:ok, assign(socket, checked: false, payload: %{})}

  @impl true
  def handle_event("record", params, socket) do
    {:noreply, assign(socket, checked: !socket.assigns.checked, payload: params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id}>
      <label>
        {@id}
        <input
          type="checkbox"
          value="on"
          checked={@checked}
          phx-click={
            if @override,
              do: Phoenix.LiveView.JS.push("record", target: @myself, value: %{value: "from-js"}),
              else: "record"
          }
          phx-target={if !@override, do: @myself}
          phx-value-id="component"
          phx-value-key="kept"
          phx-value-value="from-attribute"
        />
      </label>
      <p>{inspect(@payload)}</p>
    </section>
    """
  end
end
