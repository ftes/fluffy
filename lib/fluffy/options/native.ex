defmodule Fluffy.Options.Native do
  @moduledoc false
  # Playwright-only options follow PlaywrightEx's option docs and types, read at compile
  # time from its facade's `__options__/1` (not a stable contract: playwright_ex is pinned).

  @doc "A doc reference to `module.fun/arity`."
  def reference(module, fun, arity), do: "`#{inspect(module)}.#{fun}/#{arity}`"

  @doc "The upstream option keys of `module.fun`, without `excluded`."
  def keys(module, fun, excluded), do: for({key, _option} <- module.__options__(fun), key not in excluded, do: key)

  @doc """
  NimbleOptions entries for the upstream options of `module.fun` except `excluded`,
  documented and typed like the facade. Values are validated by the facade when the
  action runs.
  """
  def schema(module, fun, excluded) do
    for {key, option} <- module.__options__(fun), key not in excluded, do: {key, entry(option)}
  end

  @doc """
  Entries for `keys`, validated with their NimbleOptions `types`, for options that
  Fluffy compiles itself instead of passing them to the facade. A type given as a
  keyword list also replaces the documented `type_spec` and `type_doc`.
  """
  def schema(module, fun, keys, types) do
    options = module.__options__(fun)

    for key <- keys do
      entry = entry(Keyword.fetch!(options, key))

      case Keyword.fetch!(types, key) do
        [{:type, _type} | _docs] = type -> {key, Keyword.merge(entry, type)}
        type -> {key, Keyword.put(entry, :type, type)}
      end
    end
  end

  defp entry(%{type_doc: type_doc, doc: doc, spec: spec}),
    do: [type: :any, type_spec: spec, type_doc: type_doc, doc: "*Playwright only.* " <> doc]
end
