defmodule Fluffy.TestWeb.FacadeLocatorsLive do
  @moduledoc false

  use Phoenix.LiveView

  # The same markup is asserted on Static, LiveView and Playwright.
  @markups %{
    "fields" => """
    <div class="field"><label>Email <input value="a@b"></label><small>Hint one</small></div>
    <div class="field"><label>Phone <input></label><small>Hint two</small></div>
    <p hidden>Hidden</p>
    """,
    "scopes" => """
    <section id="one"><div id="inner"><p class="in">Inside</p></div></section>
    <p class="out">Outside</p>
    """,
    "forms" => """
    <section id="one"><form id="form-one" phx-submit="save"><input name="choice" value="one" aria-label="One"></form></section>
    <section id="two"><form id="form-two" phx-submit="save"><input name="choice" value="two" aria-label="Two"></form></section>
    """,
    "tracked" => """
    <section id="one"><form id="form-one" phx-submit="save"><input name="choice" aria-label="One"></form></section>
    <section id="two"></section>
    """,
    "quotes" => """
    <p id="apostrophe">Don't</p><p id="double">Say "hi"</p><p id="backtick">Run `mix`</p>
    <p id="nbsp">a&nbsp;b</p><p id="space">c d</p>
    <a href="?choice=next">Next &gt;&gt;</a><a href="?choice=later">Next &gt;&gt; later</a>
    <form method="get">
      <button name="choice" value="next">Next &gt;&gt;</button><button name="choice" value="later">Next &gt;&gt; later</button>
    </form>
    <select aria-label="Quote"><option>Don't</option><option selected>Say "hi"</option></select>
    """
  }

  def markup(name), do: Map.fetch!(@markups, name)

  @impl true
  def mount(%{"markup" => name}, _session, socket) do
    {:ok, assign(socket, name: name, saved: nil)}
  end

  @impl true
  def handle_event("save", %{"choice" => choice}, socket) do
    {:noreply, assign(socket, :saved, choice)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      {Phoenix.HTML.raw(markup(@name))}
      <p :if={@saved} id="saved">Saved {@saved}</p>
    </main>
    """
  end
end
