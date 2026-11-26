defmodule Fluffy.Support.Web.NoticeBoardLive do
  @moduledoc false

  # The board and its title change a moment after "Shuffle the notices", not in the click's
  # reply, so a test has to wait for them: a notice comes, one goes, one shows and one hides.
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, page_title: "Notice board", shuffled?: false)}

  @impl true
  def handle_event("shuffle", _params, socket) do
    Process.send_after(self(), :shuffle, 100)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:shuffle, socket), do: {:noreply, assign(socket, page_title: "Shuffled notice board", shuffled?: true)}

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <button type="button" phx-click="shuffle">Shuffle the notices</button>
      <ul>
        <li :if={not @shuffled?} id="quidditch">Quidditch trials</li>
        <li id="toad" hidden={@shuffled?}>Lost toad</li>
        <li id="detention" hidden={not @shuffled?}>Detention with Snape</li>
        <li :if={@shuffled?} id="hogsmeade">Hogsmeade weekend</li>
      </ul>
    </main>
    """
  end
end
