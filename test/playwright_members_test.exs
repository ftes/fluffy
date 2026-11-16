defmodule Fluffy.Support.PlaywrightMembersTest do
  use ExUnit.Case, async: true

  alias Fluffy.Options
  alias Fluffy.Support.PlaywrightMembers

  # Like `mix playwright_ex.parity`, for Fluffy's coverage of the PlaywrightEx facade.
  @modules [
    PlaywrightEx.Locator,
    PlaywrightEx.Expect,
    PlaywrightEx.Page,
    PlaywrightEx.Frame,
    PlaywrightEx.FrameLocator,
    PlaywrightEx.BrowserContext,
    PlaywrightEx.Keyboard,
    PlaywrightEx.Mouse,
    PlaywrightEx.Touchscreen,
    PlaywrightEx.Dialog,
    PlaywrightEx.Download,
    PlaywrightEx.FileChooser,
    PlaywrightEx.Request,
    PlaywrightEx.Response,
    PlaywrightEx.Route,
    PlaywrightEx.ConsoleMessage,
    PlaywrightEx.WebError,
    PlaywrightEx.Clock,
    PlaywrightEx.Tracing
  ]

  test "the table covers exactly the facade modules" do
    assert Enum.sort(Map.keys(PlaywrightMembers.members())) == Enum.sort(@modules)

    assert Enum.sort(Map.keys(PlaywrightMembers.events())) ==
             Enum.sort(Enum.filter(@modules, &(upstream_events(&1) != [])))
  end

  for module <- @modules do
    test "every member of #{inspect(module)} is classified once" do
      module = unquote(module)
      classified = classified(PlaywrightMembers.members(), module)
      assert_classified(module, upstream_members(module), classified, "member")
    end
  end

  test "every event is classified once" do
    for {module, _groups} <- PlaywrightMembers.events() do
      assert_classified(module, upstream_events(module), classified(PlaywrightMembers.events(), module), "event")
    end
  end

  test "wrapped and renamed members name existing Fluffy functions" do
    for {module, kind, table} <- [
          {nil, :member, PlaywrightMembers.members()},
          {:event, :event, PlaywrightMembers.events()}
        ],
        {upstream, _groups} <- table,
        {name, classification} <- classified(table, upstream) do
      counterparts = PlaywrightMembers.counterparts(module || upstream)

      case classification do
        :wrapped ->
          assert Enum.any?(counterparts, &exists?(&1, name)),
                 "#{inspect(upstream)} #{kind} #{name} is :wrapped, but none of #{inspect(counterparts)} has it"

        {:renamed, {target, fun, arity}} ->
          Code.ensure_loaded!(target)

          assert documented?(target, fun, arity),
                 "#{inspect(upstream)}.#{name} is renamed to #{inspect(target)}.#{fun}/#{arity}, which is not public"

        {class, reason} when class in [:unwrap, :denied, :na] and is_binary(reason) ->
          :ok
      end
    end
  end

  test "wrapped calls with a timeout classify their options in Fluffy.Options" do
    classified =
      for {_action, call} <- Options.native_actions() ++ Options.playwright_actions() ++ Options.native_expectations(),
          into: MapSet.new(),
          do: {elem(call, 0), elem(call, 1)}

    exceptions = PlaywrightMembers.unclassified_options()

    wrapped =
      for {module, _groups} <- PlaywrightMembers.members(),
          {fun, classification} <- classified(PlaywrightMembers.members(), module),
          classification == :wrapped or match?({:renamed, _}, classification),
          :timeout in upstream_options(module, fun),
          not negated_expectation?(module, fun),
          do: {module, fun}

    for member <- wrapped do
      assert member in classified or Map.has_key?(exceptions, member),
             "classify the upstream options of #{inspect(member)} in Fluffy.Options or unclassified_options/0"
    end

    for {member, _reason} <- exceptions do
      refute member in classified, "#{inspect(member)} is classified in Fluffy.Options; drop its exception"
      assert member in wrapped, "#{inspect(member)} is not a wrapped call with a timeout; drop its exception"
    end
  end

  defp assert_classified(module, upstream, classified, kind) do
    names = Enum.map(classified, &elem(&1, 0))
    duplicates = names -- Enum.uniq(names)
    assert duplicates == [], "#{inspect(module)} classifies #{kind}s more than once: #{inspect(duplicates)}"

    missing = upstream -- names

    assert missing == [],
           "classify the #{inspect(module)} #{kind}s #{inspect(missing)} in Fluffy.Support.PlaywrightMembers"

    stale = names -- upstream

    assert stale == [],
           "#{inspect(module)} has no #{kind}s #{inspect(stale)}; drop them from Fluffy.Support.PlaywrightMembers"
  end

  defp classified(table, module) do
    for {names, classification} <- Map.fetch!(table, module), name <- names, do: {name, classification}
  end

  defp upstream_members(module) do
    for {name, _arity} <- module.__info__(:functions),
        name = Atom.to_string(name),
        not String.starts_with?(name, "__"),
        not String.ends_with?(name, "!"),
        uniq: true,
        do: String.to_atom(name)
  end

  defp upstream_events(module) do
    {:ok, types} = Code.Typespec.fetch_types(module)

    case for({:type, {:event, type, []}} <- types, do: type) do
      [type] -> union_atoms(type)
      [] -> []
    end
  end

  defp union_atoms({:type, _line, :union, types}), do: Enum.flat_map(types, &union_atoms/1)
  defp union_atoms({:atom, _line, atom}), do: [atom]

  defp upstream_options(module, fun) do
    if function_exported?(Code.ensure_loaded!(module), :__options__, 1) do
      try do
        module |> apply(:__options__, [fun]) |> Keyword.keys()
      rescue
        FunctionClauseError -> []
      end
    else
      []
    end
  end

  defp negated_expectation?(PlaywrightEx.Expect, fun), do: fun |> Atom.to_string() |> String.starts_with?("not_")
  defp negated_expectation?(_module, _fun), do: false

  # A documented function or macro, or a field of a value struct.
  defp exists?(module, name) do
    documented?(module, name, :any) or
      (function_exported?(Code.ensure_loaded!(module), :__struct__, 0) and Map.has_key?(module.__struct__(), name))
  end

  defp documented?(module, name, arity) do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)

    Enum.any?(docs, fn {{kind, doc_name, doc_arity}, _, _, doc, _} ->
      kind in [:function, :macro] and doc_name == name and arity in [:any, doc_arity] and doc != :hidden
    end)
  end
end
