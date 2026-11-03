defmodule Fluffy.TestWeb.SubmitUsedLive do
  @moduledoc false

  use Phoenix.LiveView

  # `?upload=oversized` adds a live upload whose entries always fail with
  # too_large, so a submit is blocked by an upload entry error.
  @impl true
  def mount(params, _session, socket) do
    socket = assign(socket, form: to_form(%{}, as: :user), submits: 0, upload?: params["upload"] == "oversized")

    socket =
      if socket.assigns.upload?,
        do: allow_upload(socket, :attachment, accept: ~w(.txt), max_entries: 1, max_file_size: 16),
        else: socket

    {:ok, socket}
  end

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
      <label :if={@upload?}>Attachment <.live_file_input upload={@uploads.attachment} /></label>
      <button>Save</button>
    </form>
    <p>Submits: {@submits}</p>
    <p :if={@upload?}>Upload errors: {upload_error_count(@uploads.attachment)}</p>
    """
  end

  defp upload_error_count(upload) do
    upload.entries |> Enum.flat_map(&upload_errors(upload, &1)) |> length()
  end
end
