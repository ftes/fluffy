defmodule Fluffy.PhoenixTest do
  @moduledoc """
  A best-effort PhoenixTest vocabulary over Fluffy's existing behavior.

  Import this module on its own for the supported actions, assertions, and
  utilities. `Fluffy.Test.setup/2` lifecycle setup is still required. Alternatively,
  use `import Fluffy` with `import Fluffy.Expect` or `use Fluffy.Assert`, and
  `import Fluffy.Locator` for the regular locator API.

      import Fluffy.PhoenixTest

      start_session(:phoenix)
      |> visit("/potions")
      |> fill_in("Name", with: "Polyjuice")
      |> click_button("Save")
      |> assert_has("#notice", text: "Saved")

  This facade retains Fluffy's strictness, retries, actionability, control state,
  form serialization, and driver boundaries. Actions and assertions return a
  facade session. Field actions track their owning form for `submit/1`; navigation
  and `unwrap/2` clear that tracking. Native interoperability belongs in the
  consuming application, using the contained `session` field explicitly.

  Field actions default to exact labels; assertions default to substring labels.
  `label:` filters presence, count, text, and field-state assertions by label.
  CSS/text assertions include hidden elements and support `exact: true` for
  case-sensitive matching of the complete normalized text. `selected:` matches a
  selected option’s complete normalized text. Assertions reject multiple predicates
  and counts combined with field state. Path assertions support single-segment wildcards and flat query maps. Unsupported options raise
  `ArgumentError`. See the migration guide for the retained behavior differences.
  """

  alias Fluffy.Expect
  alias Fluffy.Locator
  alias Fluffy.PhoenixTest.Form
  alias Fluffy.Session, as: NativeSession
  alias Fluffy.URLMatcher

  defmodule Session do
    @moduledoc """
    The facade session, containing the native session, locator scope, and active form.

    Only facade operations accept this wrapper. Regular Fluffy operations require
    the contained session and explicit locators.
    """
    @enforce_keys [:session]
    defstruct [:session, :scope, :active_form, :active_form_document]

    @type t :: %__MODULE__{
            session: NativeSession.t(),
            scope: Locator.t() | nil,
            active_form: Locator.t() | nil,
            active_form_document: term()
          }
  end

  @typedoc "A facade session, or a native session accepted when entering the facade."
  @type session :: Session.t() | NativeSession.t()

  @doc "Starts an explicit Fluffy session with the selected backend."
  def start_session(backend), do: start_session(backend, [])
  @doc "Starts an explicit Fluffy session with backend options."
  def start_session(backend, options), do: %Session{session: Fluffy.start_session(backend, options)}

  @doc "Stores the Phoenix endpoint on a prepared connection."
  @spec put_endpoint(Plug.Conn.t(), module()) :: Plug.Conn.t()
  def put_endpoint(%Plug.Conn{} = conn, endpoint), do: Plug.Conn.put_private(conn, :phoenix_endpoint, endpoint)

  @doc "Visits a path. A prepared connection always starts a Phoenix session."
  @spec visit(Plug.Conn.t() | session(), String.t()) :: session()
  def visit(%Plug.Conn{} = conn, path) do
    options = [conn: conn]

    options =
      case Map.fetch(conn.private, :phoenix_endpoint) do
        {:ok, endpoint} -> Keyword.put(options, :endpoint, endpoint)
        :error -> options
      end

    :phoenix |> start_session(options) |> visit(path)
  end

  def visit(session, path), do: session |> map_session(&Fluffy.visit(&1, path)) |> clear_form()

  @doc "Clicks a link by accessible name, or by CSS and text or label (optional `exact:`)."
  @spec click_link(session(), String.t()) :: session()
  @spec click_link(session(), String.t(), String.t()) :: session()
  def click_link(session, text), do: click_role(session, :link, text)
  def click_link(session, selector, text), do: click_link(session, selector, text, [])

  @spec click_link(session(), String.t(), String.t(), keyword()) :: session()
  def click_link(session, selector, text, options), do: click_text(session, selector, text, options)

  @doc "Clicks a button by accessible name, or by CSS and text or label (optional `exact:`)."
  @spec click_button(session(), String.t()) :: session()
  @spec click_button(session(), String.t(), String.t()) :: session()
  def click_button(session, text), do: click_role(session, :button, text)
  def click_button(session, selector, text), do: click_button(session, selector, text, [])

  @spec click_button(session(), String.t(), String.t(), keyword()) :: session()
  def click_button(session, selector, text, options), do: click_text(session, selector, text, options)

  @doc "Fills a labeled field using a `String.Chars` value in `with:` and optional label `exact:`."
  @spec fill_in(session(), String.t(), keyword()) :: session()
  @spec fill_in(session(), String.t() | nil, String.t(), keyword()) :: session()
  def fill_in(session, label, options), do: fill_in(session, nil, label, options)

  def fill_in(session, selector, label, options) do
    options = options!(options, [:with, :exact])
    value = required!(options, :with)
    locator = field_locator(session, selector, label, options)
    field_action(session, locator, &Fluffy.fill(&1, locator, value))
  end

  @doc """
  Selects exact option labels with `option: value_or_list` (or legacy `from: label`).
  Each option accepts `String.Chars`. Lists replace the selected set; use `[charlist]`
  for a single charlist label. Supports label `exact:`; rejects `exact_option: false`.
  """
  @spec select(session(), String.Chars.t() | [String.Chars.t()], keyword()) :: session()
  @spec select(session(), String.t() | nil, String.Chars.t() | [String.Chars.t()], keyword()) :: session()
  def select(session, label, options), do: select(session, nil, label, options)

  def select(session, selector, label_or_option, options) do
    options = options!(options, [:option, :from, :exact, :exact_option])
    reject!(options[:exact_option] == false, "exact_option: false is unsupported")
    reject!(Keyword.has_key?(options, :option) == Keyword.has_key?(options, :from), "provide either option: or from:")

    {label, selection} =
      if Keyword.has_key?(options, :from),
        do: {options[:from], label_or_option},
        else: {label_or_option, options[:option]}

    selections = if is_list(selection), do: selection, else: [selection]
    requested = Enum.map(selections, &%{label: &1})
    locator = field_locator(session, selector, label, options)
    field_action(session, locator, &Fluffy.select_option(&1, locator, requested))
  end

  for {name, action} <- [check: :check, uncheck: :uncheck, choose: :check] do
    @doc "Changes a labeled control's checked state, with optional CSS and label `exact:`."
    @spec unquote(name)(session(), String.t()) :: session()
    @spec unquote(name)(session(), String.t(), keyword() | String.t()) :: session()
    @spec unquote(name)(session(), String.t() | nil, String.t(), keyword()) :: session()
    def unquote(name)(session, label), do: unquote(name)(session, nil, label, [])

    def unquote(name)(session, label, options) when is_list(options), do: unquote(name)(session, nil, label, options)

    def unquote(name)(session, selector, label), do: unquote(name)(session, selector, label, [])

    def unquote(name)(session, selector, label, options) do
      options = options!(options, [:exact])
      locator = field_locator(session, selector, label, options)
      field_action(session, locator, &Fluffy.unquote(action)(&1, locator))
    end
  end

  @doc """
  Selects one or more local files on a labeled input, with optional CSS and label `exact:`.
  Accepts a path string or a list of path strings, preserving selection order.
  Pass `[]` to clear the selection.

  In the four-argument form, a final keyword list (including `[]`) is interpreted
  as options. To clear using both CSS and label, use `upload(session, css, label, [], [])`.
  """
  @spec upload(session(), String.t(), String.t() | [String.t()]) :: session()
  @spec upload(session(), String.t(), String.t() | [String.t()], keyword() | String.t() | [String.t()]) :: session()
  @spec upload(session(), String.t() | nil, String.t(), String.t() | [String.t()], keyword()) :: session()
  def upload(session, label, paths), do: upload(session, nil, label, paths, [])

  def upload(session, label_or_selector, paths_or_label, options_or_paths) when is_list(options_or_paths) do
    if Keyword.keyword?(options_or_paths) do
      upload(session, nil, label_or_selector, paths_or_label, options_or_paths)
    else
      upload(session, label_or_selector, paths_or_label, options_or_paths, [])
    end
  end

  def upload(session, selector, label, paths), do: upload(session, selector, label, paths, [])

  def upload(session, selector, label, paths, options) do
    reject!(
      not (is_binary(paths) or (is_list(paths) and Enum.all?(paths, &is_binary/1))),
      "paths must be a string or a list of strings"
    )

    options = options!(options, [:exact])
    locator = field_locator(session, selector, label, options)
    field_action(session, locator, &Fluffy.set_input_files(&1, locator, paths))
  end

  @doc """
  Runs a callback with a CSS scope. Return the updated scoped session from the callback.
  Nested callbacks restore the outer scope. All operations retain the facade wrapper,
  including the last interacted field's form when leaving a scope.
  """
  @spec within(session(), String.t(), (Session.t() -> Session.t())) :: session()
  def within(session, selector, fun) when is_function(fun, 1) do
    session = wrap(session)
    scoped = %{session | scope: css_locator(session, selector)}

    case fun.(scoped) do
      %Session{} = updated -> %{updated | scope: session.scope}
      _ -> raise ArgumentError, "within callback must return a Fluffy.PhoenixTest.Session"
    end
  end

  @doc """
  Submits the form owning the most recently edited field. URL patches retain the
  active form; navigation to another document or LiveView clears it.
  """
  @spec submit(session()) :: Session.t()
  def submit(session) do
    session = wrap(session)

    case current_form(session, page_identity(session.session)) do
      %Session{active_form: nil} ->
        raise ArgumentError, "no active form; fill, select, check, choose, or upload a field first"

      %Session{active_form: locator} = session ->
        submit(session, locator)
    end
  end

  @doc "Submits an explicit CSS form selector or native form locator."
  @spec submit(session(), String.t() | Locator.t()) :: Session.t()
  def submit(session, selector) when is_binary(selector), do: submit(session, css_locator(session, selector))
  def submit(session, %Locator{} = locator), do: session |> map_session(&Fluffy.submit(&1, locator)) |> clear_form()

  @doc "Reloads the active page using the current driver."
  @spec reload_page(session()) :: session()
  def reload_page(session), do: session |> map_session(&Fluffy.reload/1) |> clear_form()

  @doc "Opens the current page using Fluffy's driver-specific browser preview."
  @spec open_browser(session()) :: session()
  def open_browser(session), do: map_session(session, &Fluffy.open_browser/1)

  @doc "Runs a native callback with Fluffy's driver-specific unwrap semantics."
  @spec unwrap(session(), (term() -> term())) :: session()
  def unwrap(session, fun), do: session |> map_session(&Fluffy.unwrap(&1, fun)) |> clear_form()

  for {name, negated?} <- [assert_has: false, refute_has: true] do
    @doc """
    Checks CSS presence or negates it, including hidden elements and multiple matches.
    Supports `text:`, text `exact:`, `count:`, one-based `at:`, `value:`, `checked:`, and `timeout:`.
    Field predicates support `label:` and label `exact:`. Only one of `text:`,
    `value:`, or `checked:` is accepted; counts cannot be combined with field state
    or `at:`. With `label:`, `at:` positions among the label-matching controls.
    The special selector `\"title\"` checks the page title and supports exact text.
    """
    @spec unquote(name)(session(), String.t()) :: session()
    @spec unquote(name)(session(), String.t(), String.t() | keyword()) :: session()
    @spec unquote(name)(session(), String.t(), String.t(), keyword()) :: session()
    def unquote(name)(session, selector), do: unquote(name)(session, selector, [])

    def unquote(name)(session, selector, options) when is_list(options) do
      expectation = has_expectation(session, selector, options)
      execute(session, expectation, unquote(negated?))
    end

    def unquote(name)(session, selector, text), do: unquote(name)(session, selector, text, [])

    def unquote(name)(session, selector, text, options) do
      options = options!(options, [:exact, :count, :at, :timeout])
      unquote(name)(session, selector, Keyword.put(options, :text, text))
    end
  end

  @doc """
  Checks a path, optionally with an exact flat `query_params:` map and `timeout:`.
  A whole `*` path segment matches one segment, including an empty segment.
  Other segments match literally. Query strings are ignored unless
  `query_params:` is supplied; fragments are always ignored.
  """
  @spec assert_path(session(), String.t(), keyword()) :: session()
  def assert_path(session, path, options \\ []), do: execute(session, path_expectation(path, options), false)

  @doc "Negates the combined path and optional query expectation."
  @spec refute_path(session(), String.t(), keyword()) :: session()
  def refute_path(session, path, options \\ []), do: execute(session, path_expectation(path, options), true)

  defp click_role(session, role, text) do
    string!(text, :text)
    locator = scoped(session, &Locator.by_role(&1, role, name: text), fn -> Locator.by_role(role, name: text) end)
    map_session(session, &Fluffy.click(&1, locator))
  end

  defp click_text(session, selector, text, options) do
    string!(text, :text)
    options = options!(options, [:exact])
    text_locator = session |> css_locator(selector) |> Locator.filter(Keyword.put(options, :has_text, text))
    label_locator = field_locator(session, selector, text, exact: Keyword.get(options, :exact, false))
    locator = Locator.or_(text_locator, label_locator)
    map_session(session, &Fluffy.click(&1, locator))
  end

  defp field_locator(session, selector, label, options) do
    string!(label, :label)
    exact = Keyword.get(options, :exact, true)

    label_locator =
      scoped(session, &Locator.by_label(&1, label, exact: exact), fn -> Locator.by_label(label, exact: exact) end)

    if is_nil(selector), do: label_locator, else: Locator.and_(css_locator(session, selector), label_locator)
  end

  defp css_locator(session, selector) do
    string!(selector, :selector)
    scoped(session, &Locator.by_css(&1, selector), fn -> Locator.by_css(selector) end)
  end

  defp scoped(%Session{scope: nil}, _scoped, unscoped), do: unscoped.()
  defp scoped(%Session{scope: scope}, scoped, _unscoped), do: scoped.(scope)
  defp scoped(%NativeSession{}, _scoped, unscoped), do: unscoped.()

  defp wrap(%Session{} = session), do: session
  defp wrap(%NativeSession{} = native), do: %Session{session: native}

  defp map_session(session, fun) do
    session = wrap(session)
    before_document = page_identity(session.session)
    session = current_form(session, before_document)
    native = fun.(session.session)
    current_form(%{session | session: native}, page_identity(native))
  end

  defp clear_form(session), do: %{session | active_form: nil, active_form_document: nil}

  # Another handle can navigate this shared page without updating the wrapper.
  defp current_form(%Session{active_form_document: document} = session, document), do: session
  defp current_form(session, _document), do: clear_form(session)

  defp page_identity(native) do
    page = NativeSession.current_page(native)
    {page.id, page.document_id}
  end

  defp field_action(session, locator, fun) do
    session = wrap(session)
    before_document = page_identity(session.session)
    form = Form.owner(session.session, locator)
    updated = map_session(session, fun)

    if page_identity(updated.session) == before_document do
      %{updated | active_form: form || Form.owner(updated.session, locator), active_form_document: before_document}
    else
      clear_form(updated)
    end
  end

  defp execute(session, expectation, negated?) do
    expectation = if negated?, do: Expect.not_(expectation), else: expectation
    map_session(session, &Expect.expect(&1, expectation))
  end

  defp has_expectation(_session, "title", options) do
    options = options!(options, [:text, :exact, :timeout])
    reject!(Keyword.has_key?(options, :exact) and not Keyword.has_key?(options, :text), "exact: requires text:")

    expected =
      case Keyword.fetch(options, :text) do
        :error -> ~r/./s
        {:ok, text} -> if options[:exact], do: text, else: Regex.compile!(Regex.escape(text))
      end

    Expect.page_to_have_title(expected, Keyword.take(options, [:timeout]))
  end

  defp has_expectation(session, selector, options) do
    options = options!(options, [:text, :exact, :count, :at, :value, :checked, :selected, :label, :timeout])
    predicates = Enum.filter([:text, :value, :checked, :selected], &Keyword.has_key?(options, &1))
    field? = Enum.any?(predicates, &(&1 in [:value, :checked, :selected]))
    reject!(length(predicates) > 1, "provide only one of text:, value:, checked:, or selected:")

    reject!(
      Keyword.has_key?(options, :count) and (field? or Keyword.has_key?(options, :at)),
      "count: cannot be combined with value:, checked:, selected:, or at:"
    )

    reject!(
      Keyword.has_key?(options, :exact) and not (Keyword.has_key?(options, :label) or Keyword.has_key?(options, :text)),
      "exact: requires label: or text:"
    )

    locator = css_locator(session, selector)

    locator =
      if Keyword.has_key?(options, :label) do
        label = field_locator(session, nil, options[:label], exact: Keyword.get(options, :exact, false))
        Locator.and_(locator, label)
      else
        locator
      end

    locator = if options[:at], do: Locator.nth(locator, options[:at] - 1), else: locator

    locator =
      if Keyword.has_key?(options, :text),
        do: Locator.filter(locator, has_text: options[:text], exact: Keyword.get(options, :exact, false)),
        else: locator

    element_expectation(locator, options)
  end

  defp element_expectation(locator, options) do
    timeout = Keyword.take(options, [:timeout])

    cond do
      Keyword.has_key?(options, :selected) ->
        locator
        |> Locator.by_css("option:checked")
        |> Locator.filter(has_text: options[:selected], exact: true)
        |> Expect.to_have_count(0, timeout)
        |> Expect.not_()

      Keyword.has_key?(options, :value) ->
        Expect.to_have_value(locator, options[:value], timeout)

      Keyword.has_key?(options, :checked) ->
        Expect.to_be_checked(locator, Keyword.put(timeout, :checked, options[:checked]))

      Keyword.has_key?(options, :count) ->
        Expect.to_have_count(locator, options[:count], timeout)

      true ->
        locator |> Expect.to_have_count(0, timeout) |> Expect.not_()
    end
  end

  defp path_expectation(path, options) do
    string!(path, :path)
    options = options!(options, [:query_params, :timeout])
    components = [path: path]

    components =
      if Keyword.has_key?(options, :query_params),
        do: Keyword.put(components, :query, query_map!(options[:query_params])),
        else: components

    parts = String.split(path, "/")

    expected =
      if "*" in parts do
        query_matcher =
          case Keyword.fetch(components, :query) do
            {:ok, query} -> URLMatcher.new!(query: query)
            :error -> nil
          end

        fn uri ->
          path_parts_match?(parts, uri.path) and
            (is_nil(query_matcher) or URLMatcher.matches?(query_matcher, URI.to_string(uri)))
        end
      else
        components
      end

    Expect.page_to_have_url(expected, Keyword.take(options, [:timeout]))
  end

  defp path_parts_match?(expected, actual) when is_binary(actual) do
    actual = String.split(actual, "/")

    length(expected) == length(actual) and
      Enum.all?(Enum.zip(expected, actual), fn {expected, actual} -> expected == "*" or expected == actual end)
  end

  defp path_parts_match?(_expected, _actual), do: false

  defp query_map!(query) when is_map(query) and not is_struct(query) do
    Map.new(query, fn {key, value} -> {query_scalar!(key), query_scalar!(value)} end)
  end

  defp query_map!(_query), do: raise(ArgumentError, "query_params: must be a flat map")

  defp query_scalar!(value) when is_binary(value) or is_atom(value) or is_number(value), do: to_string(value)

  defp query_scalar!(_value),
    do:
      raise(
        ArgumentError,
        "query_params: keys and values must be strings, atoms, or numbers; nested queries are unsupported"
      )

  defp options!(options, allowed) do
    reject!(not (is_list(options) and Keyword.keyword?(options)), "options must be a keyword list")
    keys = Keyword.keys(options)
    reject!(length(keys) != length(Enum.uniq(keys)), "duplicate options are unsupported")
    reject!(keys -- allowed != [], "unsupported options: #{inspect(keys -- allowed)}")
    Enum.each(options, &validate_option!/1)
    options
  end

  defp validate_option!({key, value}) when key in [:exact, :exact_option, :checked],
    do: reject!(not is_boolean(value), "#{key}: must be a boolean")

  defp validate_option!({key, value}) when key in [:count, :timeout],
    do: reject!(not (is_integer(value) and value >= 0), "#{key}: must be a nonnegative integer")

  defp validate_option!({:at, value}),
    do: reject!(not (is_integer(value) and value > 0), "at: must be a positive one-based position")

  defp validate_option!({key, value}) when key in [:text, :label, :value, :selected, :from], do: string!(value, key)
  defp validate_option!(_option), do: :ok

  defp required!(options, key) do
    case Keyword.fetch(options, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "missing required option #{key}:"
    end
  end

  defp string!(value, _key) when is_binary(value), do: value
  defp string!(_value, key), do: raise(ArgumentError, "#{key}: must be a string")
  defp reject!(true, message), do: raise(ArgumentError, message)
  defp reject!(false, _message), do: :ok
end
