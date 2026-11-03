defmodule Fluffy.TestWeb.SubmitUsedLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, form: to_form(%{}, as: :user), submits: 0)}

  @impl true
  def handle_event("change", %{"user" => params}, socket),
    do: {:noreply, assign(socket, form: to_form(params, as: :user))}

  def handle_event("save", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :user), submits: socket.assigns.submits + 1)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form id="submit-used" phx-change="change" phx-submit="save">
      <input type="text" name={@form[:name].name} value={@form[:name].value} aria-label="Name" />
      <input type="text" name={@form[:email].name} value={@form[:email].value} aria-label="Email" />
      <p :if={used_input?(@form[:email]) and @form[:email].value in [nil, ""]}>Email is required</p>
      <button>Save</button>
    </form>
    <p>Submits: {@submits}</p>
    """
  end
end
