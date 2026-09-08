defmodule Fluffy.TestWeb.KeyboardLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, events: [], payload_keys: "none", step: "initial", submitted: nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :step, params["step"] || "initial")}
  end

  @impl true
  def handle_event("element-keydown", params, socket) do
    {:noreply, record(socket, "element-keydown", params)}
  end

  def handle_event("element-keyup", params, socket) do
    {:noreply, record(socket, "element-keyup", params)}
  end

  def handle_event("mismatch-keydown", params, socket) do
    {:noreply, record(socket, "mismatch-keydown", params)}
  end

  def handle_event("mismatch-keyup", params, socket) do
    {:noreply, record(socket, "mismatch-keyup", params)}
  end

  def handle_event("window-keydown", params, socket) do
    {:noreply, record(socket, "window-keydown", params)}
  end

  def handle_event("window-keyup", params, socket) do
    {:noreply, record(socket, "window-keyup", params)}
  end

  def handle_event("form-keydown", params, socket) do
    {:noreply, record(socket, "form-keydown", params)}
  end

  def handle_event("tab-keydown", params, socket) do
    {:noreply, record(socket, "tab-keydown", params)}
  end

  def handle_event("tab-keyup", params, socket) do
    {:noreply, record(socket, "tab-keyup", params)}
  end

  def handle_event("space-keydown", params, socket) do
    {:noreply, record(socket, "space-keydown", params)}
  end

  def handle_event("space-keyup", params, socket) do
    {:noreply, record(socket, "space-keyup", params)}
  end

  def handle_event("payload-keydown", params, socket) do
    keys = params |> Map.keys() |> Enum.sort() |> Enum.join(",")
    {:noreply, assign(socket, :payload_keys, keys)}
  end

  def handle_event("submit", params, socket) do
    query = get_in(params, ["search", "query"])

    {:noreply,
     socket
     |> assign(:submitted, "query=#{query};commit=#{params["commit"]}")
     |> record("submit", %{"key" => nil, "value" => query, "scope" => params["commit"]})}
  end

  def handle_event("patch", _params, socket) do
    {:noreply, push_patch(socket, to: "/live/keyboard?step=patched")}
  end

  def handle_event("navigate", _params, socket) do
    {:noreply, push_navigate(socket, to: "/live/secret-chamber")}
  end

  def handle_event("crash", _params, _socket), do: raise("keyboard handler crashed")

  defp record(socket, event, params) do
    entry =
      "#{event}:key=#{display(params["key"])};value=#{display(params["value"])};" <>
        "scope=#{display(params["scope"])}"

    update(socket, :events, &(&1 ++ [entry]))
  end

  defp display(nil), do: "none"
  defp display(value), do: to_string(value)

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <label>
        Element key
        <input
          id="element-key"
          phx-keydown="element-keydown"
          phx-keyup="element-keyup"
          phx-key="eNtEr"
          phx-value-scope="element"
        />
      </label>

      <label>
        Mismatched key
        <input
          id="mismatch-key"
          phx-keydown="mismatch-keydown"
          phx-keyup="mismatch-keyup"
          phx-key="Space"
        />
      </label>

      <label>Window key <input id="window-key" /></label>
      <div
        id="window-keydown"
        phx-window-keydown="window-keydown"
        phx-key="Enter"
        phx-value-scope="window"
      />
      <div
        id="window-keyup"
        phx-window-keyup="window-keyup"
        phx-key="Enter"
        phx-value-scope="window"
      />

      <form id="search-form" phx-submit="submit">
        <label>
          Search query
          <input
            id="search-query"
            name="search[query]"
            phx-keydown="form-keydown"
            phx-key="Enter"
            phx-value-scope="form"
          />
        </label>
        <button name="commit" value="search">Search</button>
      </form>

      <label>
        Tab first <input id="tab-first" phx-keydown="tab-keydown" phx-key="Tab" />
      </label>
      <label>
        Tab second <input id="tab-second" phx-keyup="tab-keyup" phx-key="Tab" />
      </label>

      <button
        id="space-key"
        type="button"
        aria-label="Space key"
        phx-keydown="space-keydown"
        phx-keyup="space-keyup"
        phx-value-scope="space"
      >Space key target</button>
      <label>Space checkbox <input id="space-checkbox" type="checkbox" /></label>

      <label>
        Payload key
        <input
          id="payload-key"
          phx-keydown="payload-keydown"
          phx-key="Enter"
          phx-value-scope="payload"
        />
      </label>

      <form id="inline-key-form">
        <label>Inline key <input id="inline-key" onkeydown="event.preventDefault()" /></label>
        <button>Submit inline form</button>
      </form>

      <label>
        Scripted key
        <input
          id="scripted-key"
          phx-keydown={Phoenix.LiveView.JS.dispatch("custom-key")}
          phx-key="Enter"
        />
      </label>

      <.live_component module={Fluffy.TestWeb.KeyboardComponent} id="keyboard-component" />

      <label>
        Patch key <input id="patch-key" phx-keydown="patch" phx-key="Enter" />
      </label>
      <label>
        Navigate key <input id="navigate-key" phx-keydown="navigate" phx-key="Enter" />
      </label>
      <label>
        Crash key <input id="crash-key" phx-keydown="crash" phx-key="Enter" />
      </label>

      <p>Step: {@step}</p>
      <p>Submitted: {@submitted || "none"}</p>
      <p>Payload keys: {@payload_keys}</p>
      <p>Event count: {length(@events)}</p>
      <ol id="keyboard-events">
        <li :for={event <- @events}>{event}</li>
      </ol>
    </main>
    """
  end
end

defmodule Fluffy.TestWeb.KeyboardComponent do
  @moduledoc false

  use Phoenix.LiveComponent

  @impl true
  def mount(socket), do: {:ok, assign(socket, :event, "none")}

  @impl true
  def handle_event("component-keydown", params, socket) do
    event =
      "component-keydown:key=#{params["key"]};value=#{params["value"]};" <>
        "scope=#{params["scope"]}"

    {:noreply, assign(socket, :event, event)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="keyboard-component">
      <label>
        Component key
        <input
          id="component-key"
          phx-keydown={Phoenix.LiveView.JS.push("component-keydown", value: %{scope: "component"})}
          phx-key="Enter"
          phx-target={@myself}
        />
      </label>
      <p>Component event: {@event}</p>
    </section>
    """
  end
end
