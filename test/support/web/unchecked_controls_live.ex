defmodule Fluffy.Support.Web.UncheckedControlsLive do
  @moduledoc false

  use Phoenix.LiveView

  # The server renders every control's state, with no hidden inputs, so an
  # event that falls back to the rendered form instead of the browser's
  # serialization reports a control the user cleared.
  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, tags: ~w(a b), bare?: true, solo?: true, colours: ~w(red green), last: "none")}
  end

  @impl true
  def handle_event("change", params, socket), do: {:noreply, record(socket, "change", params)}
  def handle_event("save", params, socket), do: {:noreply, record(socket, "save", params)}

  def handle_event(event, %{"note" => note}, socket) when event in ~w(note-change note-save),
    do: {:noreply, assign(socket, last: "#{event} note=#{note}")}

  def handle_event("solo-change", params, socket) do
    socket = assign(socket, solo?: params["solo"] == "on")
    {:noreply, assign(socket, last: "solo #{describe(params)}")}
  end

  defp record(socket, event, params) do
    socket
    |> assign(
      tags: params["tag_ids"] || [],
      bare?: params["bare"] == "on",
      colours: params["colours"] || []
    )
    |> assign(last: "#{event} #{describe(params)}")
  end

  defp describe(params) do
    Enum.map_join(~w(tag_ids bare solo colours plan), " ", fn key ->
      "#{key}=#{params |> Map.get(key, "-") |> List.wrap() |> Enum.join(",")}"
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form id="unchecked-form" phx-change="change" phx-submit="save">
      <label :for={tag <- ~w(a b)}>
        <input type="checkbox" name="tag_ids[]" value={tag} checked={tag in @tags} /> Tag {tag}
      </label>
      <label><input type="checkbox" name="bare" checked={@bare?} /> Bare</label>
      <label><input type="checkbox" name="solo" checked={@solo?} phx-change="solo-change" /> Solo</label>
      <label for="colours">Colours</label>
      <select id="colours" name="colours[]" multiple>
        <option :for={colour <- ~w(red green)} value={colour} selected={colour in @colours}>
          {colour}
        </option>
      </select>
      <label for="plan">Plan</label>
      <select id="plan" name="plan">
        <option value="free">free</option>
        <option value="pro" selected>pro</option>
      </select>
      <button type="submit">Save</button>
    </form>
    <form id="note-form" phx-change="note-change" phx-submit="note-save" phx-value-note="meta">
      <label>Note <input name="note" value="field" /></label>
      <button type="submit">Save note</button>
    </form>
    <p id="last">Last: {@last}</p>
    """
  end
end
