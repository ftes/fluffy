defmodule Fluffy.TestWeb.ActionabilityLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket),
    do:
      {:ok,
       assign(socket,
         search: "",
         accounts_checked?: false,
         checked_keys: %{"attrs" => false, "js" => false},
         selected_creature: "none",
         confirmed?: false,
         dispatched_action: "none"
       )}

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, assign(socket, :search, search)}
  end

  def handle_event("toggle-accounts", _params, socket) do
    {:noreply, assign(socket, accounts_checked?: true)}
  end

  def handle_event("toggle-payload-checkbox", %{"id" => id}, socket) do
    {:noreply,
     update(socket, :checked_keys, fn checked_keys ->
       Map.update!(checked_keys, id, &(!&1))
     end)}
  end

  def handle_event("select-creature", %{"value" => value}, socket) do
    {:noreply, assign(socket, :selected_creature, value)}
  end

  def handle_event("confirm", _params, socket) do
    {:noreply, assign(socket, confirmed?: true)}
  end

  def handle_event("button-change", params, socket) do
    {:noreply, assign(socket, dispatched_action: params["action"] || "missing")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <style>
        .unrelated { min-width: 1px; }
      </style>
      <div class="unrelated" style="min-width: 1px">Unrelated layout-sensitive markup</div>

      <form id="actionability-form" phx-change="search">
        <label>Search bestiary <input name="search" value={@search} /></label>
      </form>

      <p id="search-result">Bestiary search: {@search}</p>

      <div style="min-width: 100%; min-height: 1px;">
        <label>Accounts
        <input type="checkbox" checked={@accounts_checked?} phx-click="toggle-accounts" /></label>
      </div>

      <p id="accounts-result">Accounts: {if @accounts_checked?, do: "checked", else: "unchecked"}</p>

      <label>
        Attribute payload
        <input
          type="checkbox"
          phx-click="toggle-payload-checkbox"
          phx-value-id="attrs"
          checked={@checked_keys["attrs"]}
        />
      </label>
      <p>Attribute payload state: {if @checked_keys["attrs"], do: "checked", else: "unchecked"}</p>

      <label>
        JS payload
        <input
          type="checkbox"
          phx-click={Phoenix.LiveView.JS.push("toggle-payload-checkbox", value: %{id: "js"})}
          checked={@checked_keys["js"]}
        />
      </label>
      <p>JS payload state: {if @checked_keys["js"], do: "checked", else: "unchecked"}</p>

      <fieldset>
        <legend>Mystic creature</legend>
        <label>
          <input
            type="radio"
            name="creature"
            value="phoenix"
            checked={@selected_creature == "phoenix"}
            phx-click="select-creature"
          /> Phoenix
        </label>
        <label>
          <input
            type="radio"
            name="creature"
            value="griffin"
            checked={@selected_creature == "griffin"}
            phx-click="select-creature"
          /> Griffin
        </label>
      </fieldset>
      <p>Selected creature: {@selected_creature}</p>

      <button type="button" data-confirm="Proceed?" phx-click="confirm">Confirm</button>
      <p id="confirm-result">{if @confirmed?, do: "confirmed", else: "unconfirmed"}</p>

      <form id="button-change-form" phx-change="button-change">
        <input type="hidden" name="query" value="current" />
        <button
          type="button"
          name="action"
          value="reset"
          phx-click={Phoenix.LiveView.JS.dispatch("change")}
        >
          Reset via change
        </button>
      </form>
      <p>Dispatched action: {@dispatched_action}</p>
    </main>
    """
  end
end
