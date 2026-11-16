defmodule Fluffy.Support.Web.NoContentLive do
  @moduledoc false

  use Phoenix.LiveView

  # `?to=` is where the plain HTTP form posts, such as a fixture answering 204.
  @impl true
  def mount(params, _session, socket) do
    {:ok, assign(socket, count: 0, to: params["to"])}
  end

  @impl true
  def handle_event("increment", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p>Count: {@count}</p>
      <button type="button" phx-click="increment">Increment</button>
      <form id="http-form" method="post" action={@to}>
        <input name="note" value="draft" aria-label="Note" />
      </form>
    </main>
    """
  end
end
