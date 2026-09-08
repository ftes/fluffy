defmodule Fluffy.Driver.Live.Keyboard do
  @moduledoc false

  alias Fluffy.CapabilityError
  alias Fluffy.ClientDOM
  alias Fluffy.HTML.Target
  alias Fluffy.Locator

  @enforce_keys [:phase, :target, :payload]
  defstruct [:phase, :target, :payload]

  @type phase :: :keydown | :keyup
  @type t :: %__MODULE__{phase: phase(), target: Target.t(), payload: map()}

  def bindings(%ClientDOM{} = client_dom, %Target{} = pressed_target, phase, key) when phase in [:keydown, :keyup] do
    key = browser_key(key)
    attribute = "phx-#{phase}"

    case event_declaration(pressed_target, attribute) do
      nil -> window_bindings(client_dom, phase, key)
      declaration -> maybe_binding(client_dom, pressed_target, phase, key, declaration)
    end
  end

  def window_bindings(%ClientDOM{} = client_dom, phase, key) when phase in [:keydown, :keyup] do
    key = browser_key(key)
    attribute = "phx-window-#{phase}"

    client_dom
    |> ClientDOM.targets(Locator.new({:css, "[#{attribute}]"}))
    |> Enum.flat_map(fn target ->
      declaration = event_declaration(target, attribute)
      maybe_binding(client_dom, target, phase, key, declaration)
    end)
  end

  defp maybe_binding(client_dom, target, phase, key, declaration) do
    if key_matches?(target, key) do
      overridden_keys = validate_declaration!(declaration)

      payload =
        client_dom
        |> ClientDOM.keyboard_payload(target, key)
        |> drop_phx_value_key(target)
        |> Map.drop(overridden_keys)

      [%__MODULE__{phase: phase, target: target, payload: payload}]
    else
      []
    end
  end

  defp event_declaration(target, attribute) do
    case attribute(target.attributes, attribute) do
      value when is_binary(value) and value != "" -> value
      _missing_or_empty -> nil
    end
  end

  defp key_matches?(target, key) do
    case attribute(target.attributes, "phx-key") do
      nil -> true
      expected -> String.downcase(expected) == String.downcase(key)
    end
  end

  defp drop_phx_value_key(payload, target) do
    case attribute(target.attributes, "phx-value-key") do
      nil -> payload
      _value -> Map.delete(payload, "key")
    end
  end

  defp validate_declaration!("[" <> _rest = encoded) do
    commands =
      try do
        Phoenix.json_library().decode!(encoded)
      rescue
        error ->
          unsupported_declaration!("invalid encoded LiveView JS command: #{Exception.message(error)}")
      end

    case commands do
      [["push", options] = command] ->
        if supported_push?(command) do
          options |> Map.get("value", %{}) |> Map.keys()
        else
          unsupported_declaration!(supported_declaration_detail())
        end

      _other ->
        unsupported_declaration!(supported_declaration_detail())
    end
  end

  defp validate_declaration!(_event_name), do: []

  defp supported_push?(["push", %{"event" => event} = options]) when is_binary(event) do
    Enum.all?(Map.keys(options), &(&1 in ["event", "target", "value"])) and
      (is_nil(options["value"]) or is_map(options["value"]))
  end

  defp supported_push?(_command), do: false

  defp browser_key("Space"), do: " "
  defp browser_key(key), do: key

  defp supported_declaration_detail do
    "in-process key bindings support event names and one LiveView JS.push command with value/target options"
  end

  defp unsupported_declaration!(detail) do
    raise CapabilityError,
      capability: :scripted_default_actions,
      driver: :live,
      detail: detail
  end

  defp attribute(attributes, name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end
end
