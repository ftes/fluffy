defmodule Fluffy.TestWeb.FileNavigationLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     assign(socket,
       action: Map.get(params, "action", "/chamber"),
       live_managed?: Map.get(params, "live_managed") == "true",
       multiple?: Map.get(params, "multiple") == "true"
     )}
  end

  @impl true
  def handle_event("save", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <form
        method="post"
        action={@action}
        enctype="multipart/form-data"
        phx-submit={if @live_managed?, do: "save"}
      >
        <label>Attachment <input type="file" name="attachment" multiple={@multiple?} /></label>
        <button name="commit" value="Save">Save</button>
      </form>
    </main>
    """
  end
end
