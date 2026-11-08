defmodule Fluffy.TestWeb.NestedParentLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket) do
    # Navigates back here a moment after connecting, without any action.
    case connected?(socket) && params["async"] do
      "return" -> Process.send_after(self(), {:return, "/live/nested?step=returned"}, 30)
      "return-late" -> Process.send_after(self(), {:return, "/live/nested?step=returned&late=true"}, 30)
      _none -> :ok
    end

    {:ok,
     assign(socket,
       late?: params["late"] == "true",
       parent_email: "",
       saved_parent_email: nil,
       parent_count: 0,
       shifted?: false,
       child_removed?: false
     )}
  end

  @impl true
  def handle_event("validate", %{"email" => email}, socket) do
    {:noreply, assign(socket, :parent_email, email)}
  end

  def handle_event("save", %{"email" => email}, socket) do
    {:noreply, assign(socket, :saved_parent_email, email)}
  end

  def handle_event("increment", _params, socket) do
    {:noreply, update(socket, :parent_count, &(&1 + 1))}
  end

  def handle_event("navigate", _params, socket) do
    {:noreply, push_navigate(socket, to: "/chamber?from=wrong-parent")}
  end

  @impl true
  def handle_info({:return, to}, socket), do: {:noreply, push_navigate(socket, to: to)}
  def handle_info(:shift_child, socket), do: {:noreply, assign(socket, :shifted?, true)}
  def handle_info(:remove_child, socket), do: {:noreply, assign(socket, :child_removed?, true)}

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <form id="parent-form" phx-change="validate" phx-submit="save">
        <label>Parent email <input name="email" value={@parent_email} /></label>
        <button type="submit">Save parent</button>
      </form>

      <p>Parent saved: {@saved_parent_email || "none"}</p>
      <p>Parent count: {@parent_count}</p>
      <p :if={@shifted?}>Child shifted</p>
      <p :if={@child_removed?}>Child removed</p>
      {if !@child_removed? do
        live_render(@socket, Fluffy.TestWeb.NestedChildLive,
          id: "nested-child",
          session: %{"late" => @late?}
        )
      end}
    </main>
    """
  end
end

defmodule Fluffy.TestWeb.NestedChildLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, session, socket) do
    # Renders the upload form a moment after connecting.
    late? = session["late"] == true
    if connected?(socket) and late?, do: Process.send_after(self(), :reveal_upload, 40)

    {:ok,
     socket
     |> allow_upload(:attachment, accept: ~w(.txt), max_entries: 1)
     |> assign(
       upload_late?: late?,
       child_email: "",
       saved_child_email: nil,
       child_count: 0,
       delayed_button?: false,
       uploaded_name: nil,
       shift_changes: 0
     )}
  end

  @impl true
  def handle_event("validate", %{"email" => email}, socket) do
    {:noreply, assign(socket, :child_email, email)}
  end

  def handle_event("save", %{"email" => email}, socket) do
    {:noreply, assign(socket, :saved_child_email, email)}
  end

  def handle_event("increment", _params, socket) do
    {:noreply, update(socket, :child_count, &(&1 + 1))}
  end

  def handle_event("schedule-button", _params, socket) do
    Process.send_after(self(), :show_delayed_button, 25)
    {:noreply, socket}
  end

  def handle_event("navigate", _params, socket) do
    {:noreply, push_navigate(socket, to: "/live/secret-chamber")}
  end

  def handle_event("patch", _params, socket) do
    {:noreply, push_patch(socket, to: "/live/nested?from=child")}
  end

  # Waits until the parent renders content before this view, so the click's
  # render moves it.
  def handle_event("shift", _params, socket) do
    send(socket.parent_pid, :shift_child)
    :sys.get_state(socket.parent_pid)
    {:noreply, socket}
  end

  # Replies only once the parent's render removing this view is on its way, so
  # LiveViewTest has dropped the view by the time this reply arrives.
  def handle_event("remove-self", _params, socket) do
    send(socket.parent_pid, :remove_child)
    :sys.get_state(socket.parent_pid)
    {:noreply, socket}
  end

  def handle_event("shift-changed", _params, socket), do: {:noreply, update(socket, :shift_changes, &(&1 + 1))}

  def handle_event("validate-upload", _params, socket), do: {:noreply, socket}

  def handle_event("save-upload", _params, socket) do
    [name] =
      consume_uploaded_entries(socket, :attachment, fn %{path: _path}, entry ->
        {:ok, entry.client_name}
      end)

    {:noreply, assign(socket, :uploaded_name, name)}
  end

  @impl true
  def handle_info(:show_delayed_button, socket) do
    {:noreply, assign(socket, :delayed_button?, true)}
  end

  def handle_info(:reveal_upload, socket), do: {:noreply, assign(socket, :upload_late?, false)}

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <form id="child-form" phx-change="validate" phx-submit="save">
        <label>Child email <input name="email" value={@child_email} /></label>
        <button type="submit">Save child</button>
      </form>

      <p>Child current: {@child_email}</p>
      <p>Child saved: {@saved_child_email || "none"}</p>
      <button type="button" phx-click="increment">Increment child</button>
      <p>Child count: {@child_count}</p>
      <button type="button" phx-click="schedule-button">Schedule child action</button>
      <button :if={@delayed_button?} type="button" phx-click="increment">Delayed child action</button>
      <button type="button" phx-click="navigate">Navigate from child</button>
      <button type="button" phx-click="patch">Patch from child</button>

      <form id="child-shift-form" phx-change="shift-changed">
        <label><input id="child-shift" type="checkbox" name="shift" phx-click="shift" /> Shift child</label>
        <label>Remove child key
        <input name="remove-self" phx-keydown="remove-self" phx-keyup="remove-self" /></label>
      </form>
      <p>Child shift changes: {@shift_changes}</p>

      <form
        :if={!@upload_late?}
        id="child-upload-form"
        phx-change="validate-upload"
        phx-submit="save-upload"
      >
        <label>Child attachment <.live_file_input upload={@uploads.attachment} /></label>
        <button type="submit">Upload child attachment</button>
      </form>
      <p>Child uploaded: {@uploaded_name || "none"}</p>
    </section>
    """
  end
end
