defmodule Fluffy.TestWeb.LiveUploadLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket) do
    mode = params["mode"]
    auto_upload? = mode in ["auto", "auto-multiple", "progress-redirect"]
    max_file_size = if mode in ["oversized", "multiple-oversized"], do: 16, else: 8_000_000
    max_entries = if mode in ["multiple", "auto-multiple", "multiple-oversized"], do: 2, else: 1

    {:ok,
     socket
     |> allow_upload(:attachment,
       accept: ~w(.txt),
       auto_upload: auto_upload?,
       max_file_size: max_file_size,
       max_entries: max_entries,
       progress: &handle_progress/3
     )
     |> assign(
       completed_uploads: 0,
       consumed: nil,
       form_removed?: false,
       input_state: :present,
       mode: mode,
       progress: 0,
       remove_on_validate?: mode == "remove-on-validate",
       saved_title: nil,
       submitted_action: nil,
       submitted_without_input?: false,
       title_disabled?: false,
       trigger_action?: false,
       validated?: false
     )}
  end

  @impl true
  def handle_event("validate", _params, %{assigns: %{remove_on_validate?: true}} = socket) do
    {:noreply, assign(socket, form_removed?: true, validated?: true)}
  end

  def handle_event("validate", _params, socket), do: {:noreply, assign(socket, validated?: true)}

  def handle_event("save", params, %{assigns: %{mode: "redirect"}} = socket) do
    socket = socket |> assign(:submitted_action, params["intent"]) |> consume_uploads()
    {:noreply, push_navigate(socket, to: "/chamber?from=upload-redirect")}
  end

  def handle_event("save", params, %{assigns: %{mode: "trigger"}} = socket) do
    socket =
      socket
      |> assign(:submitted_action, params["intent"])
      |> consume_uploads()
      |> assign(:trigger_action?, true)

    {:noreply, socket}
  end

  def handle_event("save", params, %{assigns: %{input_state: :present}} = socket) do
    socket =
      socket
      |> assign(:submitted_action, params["intent"])
      |> assign(:saved_title, params["title"] || "missing")

    case uploaded_entries(socket, :attachment) do
      {[], []} ->
        {:noreply, assign(socket, :submitted_without_input?, true)}

      {_completed, _in_progress} ->
        consumed =
          consume_uploaded_entries(socket, :attachment, fn %{path: path}, entry ->
            {:ok, %{bytes: File.read!(path), name: entry.client_name}}
          end)

        {:noreply, assign(socket, :consumed, consumed)}
    end
  end

  def handle_event("save", params, socket) do
    {:noreply,
     socket
     |> assign(:submitted_action, params["intent"])
     |> assign(:saved_title, params["title"] || "missing")
     |> assign(:submitted_without_input?, true)}
  end

  def handle_event("remove-input", _params, socket) do
    {:noreply, assign(socket, :input_state, :removed)}
  end

  def handle_event("replace-input", _params, socket) do
    {:noreply, assign(socket, :input_state, :replaced)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachment, ref)}
  end

  defp handle_progress(:attachment, entry, socket) do
    socket = assign(socket, :progress, entry.progress)

    socket =
      if entry.done? do
        update(socket, :completed_uploads, &(&1 + 1))
      else
        socket
      end

    socket =
      if socket.assigns.mode == "disable-title-on-progress" and entry.done? do
        assign(socket, :title_disabled?, true)
      else
        socket
      end

    socket =
      if socket.assigns.mode == "progress-redirect" and entry.done? do
        push_navigate(socket, to: "/chamber?from=upload-progress")
      else
        socket
      end

    {:noreply, socket}
  end

  defp consume_uploads(socket) do
    case uploaded_entries(socket, :attachment) do
      {[], []} ->
        assign(socket, :submitted_without_input?, true)

      {_completed, _in_progress} ->
        consumed =
          consume_uploaded_entries(socket, :attachment, fn %{path: path}, entry ->
            {:ok, %{bytes: File.read!(path), name: entry.client_name}}
          end)

        assign(socket, :consumed, consumed)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <form
        :if={!@form_removed?}
        id="upload-form"
        action="/chamber?from=upload-trigger"
        method="get"
        phx-change="validate"
        phx-submit="save"
        phx-trigger-action={@trigger_action?}
      >
        <label>
          Title <input name="title" value="initial" disabled={@title_disabled?} />
        </label>
        <label>
          Attachment <.live_file_input :if={@input_state == :present} upload={@uploads.attachment} />
          <input
            :if={@input_state == :replaced}
            id="replacement-attachment"
            name="attachment"
          />
        </label>
        <button type="button" phx-click="remove-input">Remove attachment</button>
        <button type="button" phx-click="replace-input">Replace attachment</button>
        <button
          :for={entry <- @uploads.attachment.entries}
          type="button"
          phx-click="cancel-upload"
          phx-value-ref={entry.ref}
        >
          Cancel upload
        </button>
        <button>Save</button>
        <button name="intent" value="draft">Draft</button>
        <a href="/chamber?from=upload-link">Leave upload form</a>
      </form>
      <p>Validated: {@validated?}</p>
      <p>Progress: {@progress}</p>
      <p>Pending uploads: {length(@uploads.attachment.entries)}</p>
      <p>Completed uploads: {@completed_uploads}</p>
      <p>Upload errors: {length(@uploads.attachment.errors)}</p>
      <p :for={entry <- @consumed || []}>Consumed: {entry.name} / {entry.bytes}</p>
      <p>Saved title: {@saved_title}</p>
      <p>Submitted action: {@submitted_action}</p>
      <p>Submitted without input: {@submitted_without_input?}</p>
    </main>
    """
  end
end
