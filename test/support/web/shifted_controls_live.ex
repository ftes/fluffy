defmodule Fluffy.TestWeb.ShiftedControlsLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket), do: {:ok, assign(socket, action: params["action"], changed?: false)}

  # File selections alone do not insert the shifting siblings, so a test can
  # pick files first and then shift them with another control.
  @impl true
  def handle_event("change", params, socket) do
    file_change? = params["_target"] in [["first_file"], ["second_file"]]
    {:noreply, assign(socket, changed?: socket.assigns.changed? or not file_change?)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form
      id="shifted-controls"
      phx-change="change"
      method="post"
      action={@action}
      enctype="multipart/form-data"
    >
      <input :if={@changed?} type="text" name="note" aria-label="Note" />
      <input type="text" name="trigger" aria-label="Trigger" />
      <input type="file" name="first_file" aria-label="First file" />
      <input type="file" name="second_file" aria-label="Second file" />
      <select :if={@changed?} name="extra" aria-label="Extra"><option>x</option><option>y</option></select>
      <select name="first" aria-label="First"><option>x</option><option>y</option></select>
      <select name="second" aria-label="Second"><option>x</option><option>y</option></select>
      <button name="commit" value="save">Save</button>
    </form>
    <p>Changed: {@changed?}</p>
    """
  end
end
