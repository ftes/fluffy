defmodule Fluffy.TestWeb.FormLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     assign(socket,
       sticky?: params["sticky"] == "true",
       colours: ["red"],
       checkbox_clicks: 0,
       debounced: "",
       direct: "",
       draft_a_id: "draft-a",
       draft_order: ["a", "b"],
       enabled: false,
       event_targets: [],
       extra?: false,
       external_trigger?: false,
       fields: %{"first" => "", "last" => ""},
       first_disabled?: false,
       first_name: "profile[first]",
       hidden_version: "version-1",
       last_event: %{},
       last_input_event: %{},
       multiple_trigger?: false,
       dynamic_trigger?: false,
       rows: [
         %{id: "a", index: "0", value: "ash"},
         %{id: "b", index: "1", value: "belladonna"},
         %{id: "c", index: "2", value: "cinder"}
       ],
       saved_commit: nil,
       saved_drop_ok?: nil,
       saved_dynamic_ok?: nil,
       saved_external: nil,
       saved_first_present?: nil,
       saved_rows: nil,
       stubborn: "server-1",
       trigger_action?: false,
       validation_saved?: false,
       version: 1
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", params, socket) do
    profile = Map.get(params, "profile", %{})
    version = socket.assigns.version + 1

    {:noreply,
     assign(socket,
       colours: List.wrap(Map.get(profile, "colours", [])),
       debounced: Map.get(profile, "debounced", socket.assigns.debounced),
       enabled: Map.get(profile, "enabled") == "yes",
       event_targets:
         socket.assigns.event_targets ++
           [target_path(Map.get(params, "_target", []))],
       fields: Map.take(profile, ["first", "last"]),
       hidden_version: "version-#{version}",
       last_event: params,
       rows: update_rows(socket.assigns.rows, Map.get(profile, "rows", %{})),
       stubborn: "server-#{version}",
       version: version
     )}
  end

  def handle_event("rotate-child-session", _params, socket), do: {:noreply, update(socket, :version, &(&1 + 1))}

  def handle_event("remove-second", _params, socket) do
    {:noreply, update(socket, :rows, &Enum.reject(&1, fn row -> row.id == "b" end))}
  end

  def handle_event("input-validate", params, socket) do
    {:noreply,
     assign(socket,
       direct: get_in(params, ["profile", "direct"]) || "",
       last_input_event: params
     )}
  end

  def handle_event("rename-and-add", _params, socket) do
    {:noreply, assign(socket, first_name: "profile[given]", extra?: true)}
  end

  def handle_event("disable-first", _params, socket) do
    {:noreply, assign(socket, :first_disabled?, true)}
  end

  def handle_event("checkbox-click", _params, socket) do
    {:noreply, update(socket, :checkbox_clicks, &(&1 + 1))}
  end

  def handle_event("reorder-drafts", _params, socket) do
    {:noreply, update(socket, :draft_order, &Enum.reverse/1)}
  end

  def handle_event("replace-draft-a", _params, socket) do
    {:noreply, assign(socket, :draft_a_id, "draft-a-replacement")}
  end

  def handle_event("trigger-from-elsewhere", _params, socket) do
    {:noreply, assign(socket, :external_trigger?, true)}
  end

  def handle_event("patch-and-trigger", _params, socket) do
    {:noreply,
     socket
     |> assign(:external_trigger?, true)
     |> push_patch(to: "/live/potions?patched=true")}
  end

  def handle_event("redirect-and-trigger", _params, socket) do
    {:noreply,
     socket
     |> assign(:external_trigger?, true)
     |> redirect(to: "/chamber?from=trigger-redirect")}
  end

  def handle_event("navigate-and-trigger", _params, socket) do
    {:noreply,
     socket
     |> assign(:external_trigger?, true)
     |> push_navigate(to: "/live/secret-chamber")}
  end

  def handle_event("trigger-multiple", _params, socket) do
    {:noreply, assign(socket, :multiple_trigger?, true)}
  end

  def handle_event("show-trigger-form", _params, socket) do
    {:noreply, assign(socket, :dynamic_trigger?, true)}
  end

  def handle_event("save", params, socket) do
    case params["commit"] do
      "redirect" -> {:noreply, push_navigate(socket, to: "/live/secret-chamber")}
      "trigger" -> {:noreply, assign(socket, :trigger_action?, true)}
      _save -> save(params, socket)
    end
  end

  def handle_event("constraint-save", _params, socket) do
    {:noreply, assign(socket, validation_saved?: true)}
  end

  defp save(params, socket) do
    profile = Map.get(params, "profile", %{})

    saved_rows =
      profile
      |> Map.get("rows", %{})
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(", ", fn {_index, row} -> row["value"] end)

    {:noreply,
     assign(socket,
       last_event: params,
       saved_commit: params["commit"],
       saved_drop_ok?: Map.get(profile, "drop") == [""],
       saved_dynamic_ok?: Map.get(profile, "given") == "moonstone" and Map.get(profile, "added") == "new",
       saved_external: Map.get(profile, "external"),
       saved_first_present?: Map.has_key?(profile, "first") or Map.has_key?(profile, "given"),
       saved_rows: saved_rows
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <section :if={@sticky?}>
        {live_render(@socket, Fluffy.TestWeb.CounterLive,
          id: "sticky-counter",
          sticky: true,
          session: %{"version" => @version}
        )}
        <.uncontrolled_form />
      </section>
      <form id="constraint-form" phx-submit="constraint-save">
        <label>Required ingredient <input name="required_value" required /></label>
        <button>Seal required potion</button>
      </form>
      <p :if={@validation_saved?}>Constrained form submitted</p>

      <form
        id="profile-form"
        method="get"
        action="/chamber"
        phx-change="validate"
        phx-submit="save"
        phx-trigger-action={@trigger_action?}
      >
        <label>
          First ingredient
          <input
            id="first"
            name={@first_name}
            value={@fields["first"]}
            disabled={@first_disabled?}
          />
        </label>
        <label>Final ingredient <input id="last" name="profile[last]" value={@fields["last"]} /></label>
        <label>
          Cauldron controlled <input id="stubborn" name="profile[stubborn]" value={@stubborn} />
        </label>
        <input id="hidden-version" type="hidden" name="profile[version]" value={@hidden_version} />
        <label>
          Debounced <input name="profile[debounced]" value={@debounced} phx-debounce="blur" />
        </label>
        <label>
          Debounced next <input name="profile[debounced_next]" phx-debounce="blur" />
        </label>
        <label>
          Direct
          <input
            name="profile[direct]"
            value={@direct}
            phx-change="input-validate"
          />
        </label>
        <label>Encoded target <input name="profile[target%20key]" /></label>
        <label>Timed <input name="profile[timed]" phx-debounce="25" /></label>
        <label>
          <input
            id="enabled"
            type="checkbox"
            name="profile[enabled]"
            value="yes"
            checked={@enabled}
            phx-click="checkbox-click"
            phx-update="ignore"
          /> Enabled
        </label>
        <label>
          Potion colours
          <select name="profile[colours][]" multiple>
            <option value="red" selected={"red" in @colours}>Red</option>
            <option value="green" selected={"green" in @colours}>Green</option>
            <option value="blue" selected={"blue" in @colours}>Blue</option>
          </select>
        </label>
        <input :if={@extra?} name="profile[added]" value="new" />

        <div :for={row <- @rows} id={"row-#{row.id}"}>
          <label>
            {"Row #{row.index}"}
            <input
              id={"row-input-#{row.id}"}
              name={"profile[rows][#{row.index}][value]"}
              value={row.value}
            />
          </label>
          <input type="hidden" name={"profile[rows][#{row.index}][id]"} value={row.id} />
        </div>

        <button
          type="button"
          name="profile[drop][]"
          value="1"
          phx-click="remove-second"
        >
          Remove row 1
        </button>
        <input type="hidden" name="profile[drop][]" value="" />
        <button type="button" phx-click="rename-and-add">Change recipe and add ingredient</button>
        <button type="button" phx-click="disable-first">Disable first ingredient</button>
        <button name="commit" value="save">Bottle potion</button>
        <button name="commit" value="redirect">Bottle and enter chamber</button>
        <button name="commit" value="trigger">Send potion over HTTP</button>
      </form>

      <input form="profile-form" name="profile[external]" value="outside" />

      <p id="last-event">Last event: {Phoenix.json_library().encode!(@last_event)}</p>
      <p>Last first: {get_in(@last_event, ["profile", "first"])}</p>
      <p>Last last: {get_in(@last_event, ["profile", "last"])}</p>
      <p>Last version: {get_in(@last_event, ["profile", "version"])}</p>
      <p>Last debounced: {get_in(@last_event, ["profile", "debounced"]) || "none"}</p>
      <p>Last target: {target_path(Map.get(@last_event, "_target", []))}</p>
      <p>Event targets: {Enum.join(@event_targets, ", ")}</p>
      <p>Unused first: {inspect(unused?(@last_event, "first"))}</p>
      <p>Unused last: {inspect(unused?(@last_event, "last"))}</p>
      <p>Input event direct: {get_in(@last_input_event, ["profile", "direct"]) || "none"}</p>
      <p>
        Input event has first: {inspect(not is_nil(get_in(@last_input_event, ["profile", "first"])))}
      </p>
      <p>Input event target: {target_path(Map.get(@last_input_event, "_target", []))}</p>
      <p>Saved rows: {@saved_rows || "not saved"}</p>
      <p>Saved drop is only empty: {inspect(@saved_drop_ok?)}</p>
      <p>Saved dynamic controls: {inspect(@saved_dynamic_ok?)}</p>
      <p>Saved external: {@saved_external || "not saved"}</p>
      <p>Saved commit: {@saved_commit || "not saved"}</p>
      <p>Saved first present: {inspect(@saved_first_present?)}</p>

      <section id="drafts">
        <div :for={draft <- @draft_order} id={"draft-row-#{draft}"}>
          <label for={if draft == "a", do: @draft_a_id, else: "draft-b"}>
            {"Potion draft #{String.upcase(draft)}"}
          </label>
          <input
            id={if draft == "a", do: @draft_a_id, else: "draft-b"}
            value={String.upcase(draft)}
            phx-keydown="reorder-drafts"
            phx-key="Enter"
          />
        </div>
      </section>
      <button type="button" phx-click="reorder-drafts">Reorder potion drafts</button>
      <button type="button" phx-click="replace-draft-a">Replace potion draft A</button>

      <p>Checkbox clicks: {@checkbox_clicks}</p>

      <form
        id="external-trigger-form"
        method="get"
        action="/chamber"
        phx-trigger-action={@external_trigger?}
      >
        <input type="hidden" name="from" value="external-trigger" />
      </form>
      <button type="button" phx-click="trigger-from-elsewhere">Trigger from elsewhere</button>
      <button type="button" phx-click="patch-and-trigger">Patch and trigger</button>
      <button type="button" phx-click="redirect-and-trigger">Redirect and trigger</button>
      <button type="button" phx-click="navigate-and-trigger">Navigate and trigger</button>

      <form method="get" action="/chamber" phx-trigger-action={@multiple_trigger?}>
        <input type="hidden" name="from" value="first-trigger" />
      </form>
      <form method="get" action="/chamber" phx-trigger-action={@multiple_trigger?}>
        <input type="hidden" name="from" value="second-trigger" />
      </form>
      <button type="button" phx-click="trigger-multiple">Trigger multiple</button>

      <form
        :if={@dynamic_trigger?}
        method="get"
        action="/chamber"
        phx-trigger-action
      >
        <input type="hidden" name="from" value="dynamic-trigger" />
      </form>
      <button type="button" phx-click="show-trigger-form">Show trigger form</button>

      <form method="get" action="/chamber">
        <input type="hidden" name="from" value="live-form" />
        <button>Leave potion lab</button>
      </form>
    </main>
    """
  end

  defp update_rows(rows, submitted) do
    Enum.map(rows, fn row ->
      case Map.get(submitted, row.index) do
        %{"value" => value} -> %{row | value: value}
        _missing -> row
      end
    end)
  end

  # Browser events encode `_target` as a list of field-name segments. The Live
  # test transport represents the same path as nested parameters.
  defp target_path(target), do: target |> target_segments() |> Enum.join("/")

  defp target_segments(target) when is_list(target), do: target
  defp target_segments(target) when is_binary(target), do: [target]

  defp target_segments(target) when is_map(target) do
    Enum.flat_map(target, fn {name, nested} -> [name | target_segments(nested)] end)
  end

  defp target_segments(_target), do: []

  defp unused?(params, name) do
    params
    |> Map.get("profile", %{})
    |> Map.has_key?("_unused_#{name}")
  end

  defp uncontrolled_form(assigns) do
    ~H"""
    <form id="uncontrolled-form" phx-change="rotate-child-session">
      <label>Uncontrolled email <input name="email" value="" /></label>
      <label>Uncontrolled name <input name="name" value="" /></label>
    </form>
    """
  end
end
