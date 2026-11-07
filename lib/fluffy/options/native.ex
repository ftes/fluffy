defmodule Fluffy.Options.Native do
  @moduledoc false
  # Playwright-only options of cross-driver actions follow PlaywrightEx's option docs
  # and types instead of copying them. `mix fluffy.gen.native_options` extracts those
  # into `Fluffy.Options.NativeGenerated`, so consumers never parse PlaywrightEx docs.

  alias Fluffy.Options.NativeGenerated

  @doc "A doc reference to `module.fun/arity`."
  def reference(module, fun, arity), do: "`#{inspect(module)}.#{fun}/#{arity}`"

  @doc """
  NimbleOptions entries for `keys`, documented and typed like the facade. Values are
  validated by the facade when the action runs.
  """
  def schema(module, fun, arity, keys) do
    options = NativeGenerated.options(module, fun, arity)

    # A key missing from stale generated data degrades to an untyped entry so the task
    # that regenerates it can still compile; the conformance tests catch staleness.
    for key <- keys do
      case Keyword.fetch(options, key) do
        {:ok, {type_doc, doc, type_spec}} ->
          {key, [type: :any, type_spec: type_spec, type_doc: type_doc, doc: "*Playwright only.* " <> doc]}

        :error ->
          {key, [type: :any, doc: "*Playwright only.*"]}
      end
    end
  end

  @doc """
  Like `schema/4`, but validated with the NimbleOptions `types` of `keys`, for options
  that Fluffy compiles itself instead of passing them to the facade. A type given as
  a keyword list also replaces the documented `type_spec` and `type_doc`.
  """
  def schema(module, fun, arity, keys, types) do
    for {key, entry} <- schema(module, fun, arity, keys) do
      case Keyword.fetch!(types, key) do
        [{:type, _type} | _docs] = type -> {key, Keyword.merge(entry, type)}
        type -> {key, Keyword.put(entry, :type, type)}
      end
    end
  end
end
