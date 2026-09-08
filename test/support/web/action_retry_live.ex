defmodule Fluffy.TestWeb.ActionRetryLive do
  @moduledoc false
  use Phoenix.LiveView

  @release_delay 50

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     assign(socket,
       navigated?: params["retry"] == "navigated",
       appeared?: false,
       fieldset_disabled?: true,
       aria_disabled?: true,
       hidden?: true,
       readonly?: true,
       checkbox_disabled?: true,
       option_present?: false,
       activated: [],
       name: "",
       checked?: false,
       plan: "basic"
     )}
  end

  @impl true
  def handle_event("schedule-release", %{"kind" => kind}, socket) do
    Process.send_after(self(), {:release, kind}, @release_delay)
    {:noreply, socket}
  end

  def handle_event("activate", %{"kind" => kind}, socket) do
    {:noreply, update(socket, :activated, &[kind | &1])}
  end

  def handle_event("change-name", %{"name" => name}, socket) do
    {:noreply, assign(socket, :name, name)}
  end

  def handle_event("check-updates", _params, socket) do
    {:noreply, assign(socket, :checked?, true)}
  end

  def handle_event("select-plan", %{"plan" => plan}, socket) do
    {:noreply, assign(socket, :plan, plan)}
  end

  def handle_event("schedule-option", _params, socket) do
    Process.send_after(self(), {:release, "option"}, @release_delay)
    {:noreply, socket}
  end

  def handle_event("schedule-navigation", _params, socket) do
    Process.send_after(self(), :retry_navigation, @release_delay)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:release, "appeared"}, socket) do
    {:noreply, assign(socket, :appeared?, true)}
  end

  def handle_info({:release, "fieldset"}, socket) do
    {:noreply, assign(socket, :fieldset_disabled?, false)}
  end

  def handle_info({:release, "aria"}, socket) do
    {:noreply, assign(socket, :aria_disabled?, false)}
  end

  def handle_info({:release, "hidden"}, socket) do
    {:noreply, assign(socket, :hidden?, false)}
  end

  def handle_info({:release, "readonly"}, socket) do
    {:noreply, assign(socket, :readonly?, false)}
  end

  def handle_info({:release, "checkbox"}, socket) do
    {:noreply, assign(socket, :checkbox_disabled?, false)}
  end

  def handle_info({:release, "option"}, socket) do
    {:noreply, assign(socket, :option_present?, true)}
  end

  def handle_info(:retry_navigation, socket) do
    {:noreply, push_navigate(socket, to: "/live/action-retries?retry=navigated")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <button type="button" phx-click="schedule-navigation">Release by navigation</button>
      <button
        :if={@navigated?}
        id="retry-across-navigation"
        type="button"
        phx-click="activate"
        phx-value-kind="navigated"
      >
        Action after navigation
      </button>
      <p>Navigation retry result: {activated?(@activated, "navigated")}</p>

      <button type="button" phx-click="schedule-release" phx-value-kind="appeared">
        Release appearing button
      </button>
      <button :if={@appeared?} type="button" phx-click="activate" phx-value-kind="appeared">
        Appearing action
      </button>
      <p>Appearing result: {activated?(@activated, "appeared")}</p>

      <button type="button" phx-click="schedule-release" phx-value-kind="fieldset">
        Release fieldset button
      </button>
      <fieldset disabled={@fieldset_disabled?}>
        <button type="button" phx-click="activate" phx-value-kind="fieldset">
          Fieldset action
        </button>
      </fieldset>
      <p>Fieldset result: {activated?(@activated, "fieldset")}</p>

      <button type="button" phx-click="schedule-release" phx-value-kind="aria">
        Release ARIA button
      </button>
      <button
        type="button"
        aria-disabled={to_string(@aria_disabled?)}
        phx-click="activate"
        phx-value-kind="aria"
      >
        ARIA action
      </button>
      <p>ARIA result: {activated?(@activated, "aria")}</p>

      <button type="button" phx-click="schedule-release" phx-value-kind="hidden">
        Release hidden button
      </button>
      <button
        id="hidden-action"
        type="button"
        hidden={@hidden?}
        phx-click="activate"
        phx-value-kind="hidden"
      >
        Hidden action
      </button>
      <p>Hidden result: {activated?(@activated, "hidden")}</p>

      <button type="button" phx-click="schedule-release" phx-value-kind="readonly">
        Release readonly field
      </button>
      <form id="retry-name-form" phx-change="change-name">
        <label>Name <input name="name" value={@name} readonly={@readonly?} /></label>
      </form>
      <p>Name result: {@name}</p>

      <button type="button" phx-click="schedule-release" phx-value-kind="checkbox">
        Release checkbox
      </button>
      <label>
        Updates
        <input
          type="checkbox"
          disabled={@checkbox_disabled?}
          checked={@checked?}
          phx-click="check-updates"
        />
      </label>
      <p>Updates result: {if @checked?, do: "checked", else: "unchecked"}</p>

      <form id="option-release-form" phx-change="schedule-option">
        <label>Reveal Phoenix Tonic <input type="checkbox" name="include_pro" /></label>
      </form>
      <form id="retry-plan-form" phx-change="select-plan">
        <label for="retry-plan">Potion</label>
        <select id="retry-plan" name="plan">
          <option value="basic" selected={@plan == "basic"}>Sleeping Draught</option>
          <option :if={@option_present?} value="pro" selected={@plan == "pro"}>Phoenix Tonic</option>
        </select>
      </form>
      <p>Potion result: {@plan}</p>

      <button id="permanently-disabled" type="button" disabled>Never enabled</button>
      <input id="permanently-readonly" aria-label="Never writable" readonly />
      <button id="wrong-fill-target" type="button">Wrong fill target</button>
      <button id="readonly-wrong-fill-target" type="button" readonly>
        Readonly wrong fill target
      </button>
      <select id="permanent-plan" aria-label="Permanent potion">
        <option value="basic">Sleeping Draught</option>
        <option value="disabled" disabled>Disabled</option>
      </select>
      <button class="ambiguous">Ambiguous action</button>
      <button class="ambiguous">Ambiguous action</button>
    </main>
    """
  end

  defp activated?(activated, kind), do: if(kind in activated, do: "activated", else: "waiting")
end
