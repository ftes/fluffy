defmodule Fluffy.TestWeb.PatchingKeyComponent do
  @moduledoc false
  use Phoenix.LiveComponent

  # The parent removes this component while the keydown's reply is on its way.
  @impl true
  def handle_event("component-keydown", _params, socket) do
    send(self(), :remove_key_component)
    {:noreply, socket}
  end

  def handle_event("component-keyup", _params, socket) do
    send(self(), :component_keyup)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="key-component">
      <label>
        Component keys
        <input
          type="text"
          name="component-keys"
          phx-keydown="component-keydown"
          phx-keyup="component-keyup"
          phx-target={@myself}
        />
      </label>
    </section>
    """
  end
end

defmodule Fluffy.TestWeb.PatchingLive do
  @moduledoc false
  use Phoenix.LiveView

  @upload_modes ~w(submit progress auto-change progress-insert progress-insert-form progress-remove auto-remove input-hide validate-insert idless-insert)

  @impl true
  def mount(%{"mode" => mode}, _session, socket) do
    socket =
      assign(socket,
        mode: mode,
        keyups: 0,
        inserted_keyups: 0,
        row_inserted?: false,
        row_label: "Row keys",
        changes: 0,
        saves: 0,
        consumed: 0,
        uploaded: 0,
        banner?: false,
        other_form?: false,
        input_hidden?: false,
        removed?: false,
        keys_label: "Keys",
        keyup_event: "keyup",
        rows: if(mode in ~w(rows-remove rows-append), do: ~w(a b), else: ~w(a)),
        row_keyups: [],
        component_removed?: false,
        component_keyups: 0
      )

    socket =
      if mode in @upload_modes do
        allow_upload(socket, :attachment,
          accept: ~w(.txt),
          max_entries: 2,
          auto_upload: mode in ~w(auto-change auto-remove),
          progress: &handle_progress/3
        )
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:remove_key_component, socket), do: {:noreply, assign(socket, :component_removed?, true)}
  def handle_info(:component_keyup, socket), do: {:noreply, update(socket, :component_keyups, &(&1 + 1))}

  defp handle_progress(:attachment, %{done?: true}, socket) do
    socket = update(socket, :uploaded, &(&1 + 1))

    case socket.assigns.mode do
      "progress" ->
        {:noreply, patch(socket, "uploaded")}

      mode when mode in ~w(progress-insert idless-insert) ->
        {:noreply, socket |> assign(:banner?, true) |> patch("uploaded")}

      "progress-insert-form" ->
        {:noreply, socket |> assign(:other_form?, true) |> patch("uploaded")}

      "input-hide" ->
        {:noreply, assign(socket, :input_hidden?, true)}

      mode when mode in ~w(progress-remove auto-remove) ->
        {:noreply, socket |> assign(:removed?, true) |> patch("uploaded")}

      _other ->
        {:noreply, socket}
    end
  end

  defp handle_progress(:attachment, _entry, socket), do: {:noreply, socket}

  defp patch(socket, step), do: push_patch(socket, to: "/live/patching/#{socket.assigns.mode}?step=#{step}")

  @impl true
  def handle_event("keydown", _params, %{assigns: %{mode: "keydown-remove"}} = socket) do
    {:noreply, socket |> assign(:removed?, true) |> patch("keydown")}
  end

  def handle_event("keydown", _params, %{assigns: %{mode: "keydown-unbind"}} = socket) do
    {:noreply, socket |> assign(:keyup_event, nil) |> patch("keydown")}
  end

  def handle_event("keydown", _params, %{assigns: %{mode: "keydown-rename"}} = socket) do
    {:noreply, socket |> assign(:keys_label, "Pressed") |> patch("keydown")}
  end

  def handle_event("keydown", _params, %{assigns: %{mode: "keydown-remove-unpatched"}} = socket) do
    {:noreply, assign(socket, :removed?, true)}
  end

  def handle_event("keydown", _params, socket), do: {:noreply, patch(socket, "keydown")}

  def handle_event("rows-keydown", %{"row" => row}, socket) do
    rows =
      case socket.assigns.mode do
        "rows-remove" -> List.delete(socket.assigns.rows, row)
        "rows-prepend" -> ["z" | socket.assigns.rows]
        "rows-append" -> socket.assigns.rows ++ ["c"]
      end

    {:noreply, assign(socket, :rows, rows)}
  end

  def handle_event("rows-keyup", %{"row" => row}, socket) do
    {:noreply, update(socket, :row_keyups, &(&1 ++ [row]))}
  end

  def handle_event("row-keydown", _params, %{assigns: %{mode: "idless-rename"}} = socket) do
    {:noreply, assign(socket, :row_label, "Pressed row")}
  end

  def handle_event("row-keydown", _params, socket), do: {:noreply, assign(socket, :row_inserted?, true)}
  def handle_event("inserted-keyup", _params, socket), do: {:noreply, update(socket, :inserted_keyups, &(&1 + 1))}
  def handle_event("keyup", _params, socket), do: {:noreply, update(socket, :keyups, &(&1 + 1))}
  def handle_event("toggle", _params, socket), do: {:noreply, patch(socket, "toggled")}
  def handle_event("change", _params, socket), do: {:noreply, update(socket, :changes, &(&1 + 1))}

  def handle_event("validate", _params, %{assigns: %{mode: "auto-change"}} = socket) do
    {:noreply, patch(socket, "validated")}
  end

  def handle_event("validate", _params, %{assigns: %{mode: "validate-insert"}} = socket) do
    {:noreply, assign(socket, :banner?, true)}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("save", _params, socket) do
    consumed = consume_uploaded_entries(socket, :attachment, fn _meta, entry -> {:ok, entry.client_name} end)
    socket = socket |> update(:saves, &(&1 + 1)) |> update(:consumed, &(&1 + length(consumed)))
    if socket.assigns.mode == "submit", do: {:noreply, patch(socket, "saved")}, else: {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p :if={@banner?}>Upload received</p>
      <p>Keyups: {@keyups}</p>
      <p>Inserted keyups: {@inserted_keyups}</p>
      <p>Changes: {@changes}</p>
      <p>Saves: {@saves}</p>
      <p>Consumed: {@consumed}</p>
      <p>Uploaded: {@uploaded}</p>
      <p>Row keyups: {Enum.join(@row_keyups, ",")}.</p>
      <p>Component keyups: {@component_keyups}</p>
      <.live_component
        :if={@mode == "component-myself" && !@component_removed?}
        module={Fluffy.TestWeb.PatchingKeyComponent}
        id="key-component"
      />
      <div :for={row <- @rows} :if={String.starts_with?(@mode, "rows-")}>
        <label>
          Twin
          <input
            type="text"
            name="twin"
            phx-keydown="rows-keydown"
            phx-keyup="rows-keyup"
            phx-value-row={row}
          />
        </label>
      </div>
      <div :if={@row_inserted? && @mode == "idless-row"}>
        <label>Inserted <input type="text" name="inserted" phx-keyup="inserted-keyup" /></label>
      </div>
      <div :if={@row_inserted? && @mode == "idless-wrapper"}>Inserted row</div>
      <div :if={@mode in ~w(idless-row idless-wrapper idless-rename idless-append)}>
        <label>{@row_label}
        <input type="text" name="row" phx-keydown="row-keydown" phx-keyup="keyup" /></label>
      </div>
      <div :if={@row_inserted? && @mode == "idless-append"}>
        <label>Row keys <input type="text" name="appended" phx-keyup="inserted-keyup" /></label>
      </div>
      <label :if={!@removed?}>{@keys_label}
      <input type="text" id="keys" name="keys" phx-keydown="keydown" phx-keyup={@keyup_event} /></label>
      <form id="toggle-form" phx-change="change">
        <label>Toggle <input type="checkbox" name="agree" phx-click="toggle" /></label>
      </form>
      <form :if={@other_form?} id="other-form"></form>
      <div :if={@mode == "idless-insert" && @banner?}>Wrapper before the form</div>
      <div>
        <form
          :if={assigns[:uploads] && !@removed?}
          id={if @mode != "idless-insert", do: "upload-form"}
          phx-change="validate"
          phx-submit="save"
        >
          <label :if={!@input_hidden?}>Attachment <.live_file_input upload={@uploads.attachment} /></label>
          <button type="submit">Save</button>
        </form>
      </div>
    </main>
    """
  end
end
