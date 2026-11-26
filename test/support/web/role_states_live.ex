defmodule Fluffy.Support.Web.RoleStatesLive do
  @moduledoc false

  use Phoenix.LiveView

  # Role states for `by_role`'s options, asserted on Static, LiveView and Playwright.
  @markup """
  <h1>Hogwarts</h1>
  <h2 aria-level="5">Great Hall</h2>
  <h6>Fat Lady</h6>
  <div role="heading" aria-level="3">Common room</div>
  <div role="heading" aria-level="seventh">Dormitory</div>
  <ul><li aria-level="2">Owlery</li></ul>

  <fieldset>
    <legend>Spells</legend>
    <label><input type="checkbox" checked> Lumos</label>
    <label><input type="checkbox"> Nox</label>
  </fieldset>
  <fieldset>
    <legend>House</legend>
    <label><input type="radio" name="house" checked> Gryffindor</label>
    <label><input type="radio" name="house"> Slytherin</label>
  </fieldset>
  <div role="checkbox" aria-checked="true" tabindex="0">Invisibility Cloak</div>
  <div role="switch" aria-checked="false" tabindex="0">Time-Turner</div>
  <div role="menu" aria-label="Maps"><div role="menuitemcheckbox" aria-checked="mixed">Marauder's Map</div></div>

  <label for="wand">Wand</label>
  <select id="wand"><option>Holly</option><option selected>Elder</option><option>Vine</option></select>
  <select aria-label="Pets" multiple><option selected>Toad</option><option>Cat</option><option selected>Rat</option></select>
  <select aria-label="Owls"><option>Hedwig</option><option>Errol</option></select>
  <input list="ingredients" aria-label="Ingredient">
  <datalist id="ingredients"><option selected>Mandrake root</option><option>Bezoar</option></datalist>
  <div role="listbox" aria-label="Brooms">
    <div role="option" aria-selected="true">Firebolt</div>
    <div role="option" aria-selected="false">Nimbus</div>
  </div>
  <div role="tablist"><div role="tab" aria-selected="true">Charms</div><div role="tab">Potions</div></div>

  <button disabled>Restricted Section</button>
  <button aria-disabled="true">Forbidden Forest</button>
  <div aria-disabled="true"><button>Chamber of Secrets</button></div>
  <fieldset disabled>
    <legend><button>Prefects' Bathroom</button></legend>
    <button>Quidditch Pitch</button>
    <legend><button>Astronomy Tower</button></legend>
  </fieldset>
  <select aria-label="Wand shop"><optgroup label="Sold" disabled><option>Unicorn hair</option></optgroup></select>

  <button aria-expanded="true">Sorting Hat</button>
  <button aria-expanded="false">Pensieve</button>
  <button aria-pressed="true">Silencio</button>
  <button aria-pressed="false">Sonorus</button>
  <button aria-pressed="mixed">Riddikulus</button>

  <button aria-describedby="alohomora-hint">Alohomora</button>
  <p id="alohomora-hint">Unlocks   doors</p>
  <button title="Lights the wand tip">Lumos Maxima</button>
  <button aria-description="Disarms an opponent">Expelliarmus</button>
  <button aria-describedby="obliviate-hint">Obliviate</button>
  <p id="obliviate-hint" hidden>Erases memories</p>

  <button hidden>Room of Requirement</button>
  <div aria-hidden="true"><button>Platform Nine and Three-Quarters</button></div>
  <button>Accio<span hidden> Firebolt</span></button>
  """

  def markup, do: @markup

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <main>{Phoenix.HTML.raw(markup())}</main>
    """
  end
end
