defmodule Fluffy.TestWeb.DatabaseLive do
  @moduledoc false

  use Phoenix.LiveView

  alias Fluffy.TestRepo
  alias Fluffy.TestWeb.DatabaseComponent

  @impl true
  def mount(params, _session, socket) do
    delay = String.to_integer(params["delay"] || "30")

    {:ok,
     socket
     |> assign(:values, values())
     |> assign_async(:async_count, fn -> {:ok, %{async_count: count()}} end)
     |> assign_async(:delayed_count, fn ->
       Process.sleep(delay)
       {:ok, %{delayed_count: count()}}
     end)}
  end

  @impl true
  def handle_event("insert", _params, socket) do
    TestRepo.query!("INSERT INTO fluffy_records (value) VALUES ('event')")
    send_update(DatabaseComponent, id: "database-count")
    {:noreply, assign(socket, :values, values())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p>Live values: {Enum.join(@values, ", ")}</p>
      <button type="button" phx-click="insert">Insert event</button>
      <.live_component module={DatabaseComponent} id="database-count" />
      <.async_result :let={count} assign={@async_count}>
        <:loading>Async count: loading</:loading>
        Async count: {count}
      </.async_result>
      <.async_result :let={count} assign={@delayed_count}>
        <:loading>Delayed count: loading</:loading>
        Delayed count: {count}
      </.async_result>
      {live_render(@socket, Fluffy.TestWeb.DatabaseNestedLive, id: "database-nested")}
      <a href="/database">Back to database page</a>
    </main>
    """
  end

  defp values do
    %{rows: rows} = TestRepo.query!("SELECT value FROM fluffy_records ORDER BY value")
    Enum.map(rows, &hd/1)
  end

  defp count do
    %{rows: [[count]]} = TestRepo.query!("SELECT count(*) FROM fluffy_records")
    count
  end
end

defmodule Fluffy.TestWeb.DatabaseNestedLive do
  @moduledoc false

  use Phoenix.LiveView

  alias Fluffy.TestRepo

  on_mount(Fluffy.Sandbox)

  @impl true
  def mount(_params, _session, socket) do
    %{rows: [[count]]} = TestRepo.query!("SELECT count(*) FROM fluffy_records")
    {:ok, assign(socket, :count, count)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <p>Nested count: {@count}</p>
    """
  end
end

defmodule Fluffy.TestWeb.DatabaseComponent do
  @moduledoc false

  use Phoenix.LiveComponent

  alias Fluffy.TestRepo

  @impl true
  def update(assigns, socket) do
    %{rows: [[count]]} = TestRepo.query!("SELECT count(*) FROM fluffy_records")
    {:ok, socket |> assign(assigns) |> assign(:count, count)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <p>Component count: {@count}</p>
    """
  end
end
