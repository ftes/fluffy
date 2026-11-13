defmodule Fluffy.PhoenixTest do
  @moduledoc """
  A PhoenixTest-style facade over Fluffy's actions and assertions.

  Import this module on its own to keep familiar PhoenixTest helper names with
  either backend. See [Coming from PhoenixTest](migration-from-phoenix-test.md)
  for migration setup, examples, and compatibility differences.

  Actions and assertions return a `Fluffy.PhoenixTest.Session`. Native Fluffy
  APIs accept its contained `session` field. The function documentation below
  defines the supported overloads and options; unsupported options raise
  `ArgumentError`. Exact text (`exact: true`) normalizes whitespace but, unlike native
  exact matching, does not ignore soft hyphens or zero-width spaces in the page text.

      conn
      |> visit("/creatures/new")
      |> fill_in("Name", with: "Basilisk")
      |> click_button("Register")
      |> assert_has("#notice", text: "Creature registered")
  """
  @moduledoc groups: ["Lifecycle and navigation", "Actions", "Assertions", "Diagnostics and native access"]

  alias Fluffy.Expect
  alias Fluffy.Locator
  alias Fluffy.PhoenixTest.Form
  alias Fluffy.Session, as: NativeSession

  @non_file_buttons "button, input:not([type=file i]), [role]:not(input)"

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

  @doc group: "Lifecycle and navigation"
  @doc "Starts an explicit Fluffy session with the selected backend."
  def start_session(backend), do: start_session(backend, [])
  @doc group: "Lifecycle and navigation"
  @doc "Starts an explicit Fluffy session with backend options."
  def start_session(backend, options), do: %Session{session: Fluffy.start_session(backend, options)}

  @doc group: "Lifecycle and navigation"
  @doc "Stores the Phoenix endpoint on a prepared connection."
  @spec put_endpoint(Plug.Conn.t(), module()) :: Plug.Conn.t()
  def put_endpoint(%Plug.Conn{} = conn, endpoint), do: Plug.Conn.put_private(conn, :phoenix_endpoint, endpoint)

  @doc group: "Lifecycle and navigation"
  @doc """
  Visits a path. A connection always starts a Phoenix session.
  Used connections are recycled automatically; fresh prepared connections are preserved.
  """
  @spec visit(Plug.Conn.t() | session(), String.t()) :: session()
  def visit(%Plug.Conn{} = conn, path) do
    options = [conn: Phoenix.ConnTest.ensure_recycled(conn)]

    options =
      case Map.fetch(conn.private, :phoenix_endpoint) do
        {:ok, endpoint} -> Keyword.put(options, :endpoint, endpoint)
        :error -> options
      end

    :phoenix |> start_session(options) |> visit(path)
  end

  def visit(session, path), do: session |> map_session(&Fluffy.visit(&1, path)) |> clear_form()

  @doc group: "Actions"
  @doc """
  Clicks a link by accessible name, or by CSS and text (optional `exact:`).
  CSS links fall back to label matching only when no text match exists at the
  time of the call. Ambiguous or non-actionable text matches do not trigger fallback.
  """
  @spec click_link(session(), String.t()) :: session()
  @spec click_link(session(), String.t(), String.t()) :: session()
  def click_link(session, text), do: click_locator(session, role_locator(session, :link, text))
  @doc group: "Actions"
  @doc "Like `click_link/2`, by CSS `selector` and link `text`."
  def click_link(session, selector, text), do: click_link(session, selector, text, [])

  @doc group: "Actions"
  @doc "Like `click_link/3`, with `exact:` for matching `text`."
  @spec click_link(session(), String.t(), String.t(), keyword()) :: session()
  def click_link(session, selector, text, options) do
    {text_locator, label_locator} = text_and_label_locators(session, selector, text, options)

    map_session(session, fn native ->
      locator = if Fluffy.PhoenixTest.Query.matches?(native, text_locator), do: text_locator, else: label_locator

      Fluffy.click(native, locator)
    end)
  end

  @doc group: "Actions"
  @doc "Clicks a button by accessible name, or by CSS and text or label (optional `exact:`)."
  @spec click_button(session(), String.t()) :: session()
  @spec click_button(session(), String.t(), String.t()) :: session()
  def click_button(session, text) do
    # `by_role(:button)` matches a file input, as in Playwright; `click_button` never means one.
    buttons = css_locator(session, @non_file_buttons)
    click_locator(session, session |> role_locator(:button, text) |> Locator.and_(buttons))
  end

  @doc group: "Actions"
  @doc "Like `click_button/2`, by CSS `selector` and button text or label."
  def click_button(session, selector, text), do: click_button(session, selector, text, [])

  @doc group: "Actions"
  @doc "Like `click_button/3`, with `exact:` for matching `text`."
  @spec click_button(session(), String.t(), String.t(), keyword()) :: session()
  def click_button(session, selector, text, options), do: click_text(session, selector, text, options)

  @doc group: "Actions"
  @doc "Fills a labeled field using a `String.Chars` value in `with:` and optional label `exact:`."
  @spec fill_in(session(), String.t(), keyword()) :: session()
  @spec fill_in(session(), String.t() | nil, String.t(), keyword()) :: session()
  def fill_in(session, label, options), do: fill_in(session, nil, label, options)

  @doc group: "Actions"
  @doc "Like `fill_in/3`, where the field must also match the CSS `selector` (`nil` for none)."
  def fill_in(session, selector, label, options) do
    options = options!(options, [:with, :exact])
    value = required!(options, :with)
    locator = field_locator(session, selector, label, options)
    field_action(session, locator, &Fluffy.fill(&1, locator, value))
  end

  @doc group: "Actions"
  @doc """
  Selects exact option labels with `option: value_or_list` (or legacy `from: label`).
  Each option accepts `String.Chars`. Lists replace the selected set; use `[charlist]`
  for a single charlist label. Supports label `exact:`; rejects `exact_option: false`.
  """
  @spec select(session(), String.Chars.t() | [String.Chars.t()], keyword()) :: session()
  @spec select(session(), String.t() | nil, String.Chars.t() | [String.Chars.t()], keyword()) :: session()
  def select(session, label, options), do: select(session, nil, label, options)

  @doc group: "Actions"
  @doc "Like `select/3`, where the field must also match the CSS `selector` (`nil` for none)."
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
    @doc group: "Actions"
    @doc "Changes a labeled control's checked state, with optional CSS and label `exact:`."
    @spec unquote(name)(session(), String.t()) :: session()
    @spec unquote(name)(session(), String.t(), keyword() | String.t()) :: session()
    @spec unquote(name)(session(), String.t() | nil, String.t(), keyword()) :: session()
    def unquote(name)(session, label), do: unquote(name)(session, nil, label, [])

    @doc group: "Actions"
    @doc "Like `#{name}/2`, with `exact:` options after the label, or a CSS `selector` before it."
    def unquote(name)(session, label, options) when is_list(options), do: unquote(name)(session, nil, label, options)

    def unquote(name)(session, selector, label), do: unquote(name)(session, selector, label, [])

    @doc group: "Actions"
    @doc "Like `#{name}/2`, with a CSS `selector` (`nil` for none) the control must also match, and label `exact:`."
    def unquote(name)(session, selector, label, options) do
      options = options!(options, [:exact])
      locator = field_locator(session, selector, label, options)
      field_action(session, locator, &Fluffy.unquote(action)(&1, locator))
    end
  end

  @doc group: "Actions"
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

  @doc group: "Actions"
  @doc "Like `upload/3`, with a final keyword list as label `exact:` options, or a CSS `selector` before the label."
  def upload(session, label_or_selector, paths_or_label, options_or_paths) when is_list(options_or_paths) do
    if Keyword.keyword?(options_or_paths) do
      upload(session, nil, label_or_selector, paths_or_label, options_or_paths)
    else
      upload(session, label_or_selector, paths_or_label, options_or_paths, [])
    end
  end

  def upload(session, selector, label, paths), do: upload(session, selector, label, paths, [])

  @doc group: "Actions"
  @doc "Like `upload/3`, with a CSS `selector` (`nil` for none) and label `exact:` options."
  def upload(session, selector, label, paths, options) do
    reject!(
      not (is_binary(paths) or (is_list(paths) and Enum.all?(paths, &is_binary/1))),
      "paths must be a string or a list of strings"
    )

    options = options!(options, [:exact])
    locator = field_locator(session, selector, label, options)
    field_action(session, locator, &Fluffy.set_input_files(&1, locator, paths))
  end

  @doc group: "Actions"
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

  @doc group: "Actions"
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
        submit_form(session, locator)
    end
  end

  @doc group: "Actions"
  @doc "Submits an explicit CSS form selector or native form locator, inside the current `within/3` scope."
  @spec submit(session(), String.t() | Locator.t()) :: Session.t()
  def submit(session, selector), do: submit_form(session, locator_in_scope(session, base_locator(selector)))

  defp submit_form(session, locator), do: session |> map_session(&Fluffy.submit(&1, locator)) |> clear_form()

  @doc group: "Lifecycle and navigation"
  @doc "Reloads the active page using the current driver."
  @spec reload_page(session()) :: session()
  def reload_page(session), do: session |> map_session(&Fluffy.reload/1) |> clear_form()

  @doc group: "Diagnostics and native access"
  @doc "Opens the current page using Fluffy's driver-specific browser preview."
  @spec open_browser(session()) :: session()
  def open_browser(session), do: map_session(session, &Fluffy.open_browser/1)

  @doc group: "Diagnostics and native access"
  @doc "Runs a native callback with Fluffy's driver-specific unwrap semantics."
  @spec unwrap(session(), (term() -> term())) :: session()
  def unwrap(session, fun), do: session |> map_session(&Fluffy.unwrap(&1, fun)) |> clear_form()

  @doc group: "Diagnostics and native access"
  @doc """
  Runs a native callback like `unwrap/2` and returns the callback's result instead of the session.
  Keep using the same session afterwards: on LiveView and Playwright, navigation the callback
  causes is still followed. A Static page stays as it is, whatever `Plug.Conn` the callback returns.

  The result cannot carry the session wrapper back, so the form `submit/1` would use is not
  updated. If the callback replaces that form without navigating, use `unwrap/2`.
  """
  @spec unwrap_and_return(session(), (term() -> result)) :: result when result: term()
  def unwrap_and_return(session, fun), do: Fluffy.unwrap_and_return(wrap(session).session, fun)

  for {name, negated?} <- [assert_has: false, refute_has: true] do
    @doc group: "Assertions"
    @doc """
    Checks whether any CSS or `Fluffy.Locator` match is visible, or negates that check.
    A locator resolves inside the current `within/3` scope and takes the same options.
    Multiple matches are allowed; refutation requires every match to be hidden or absent.
    Static and Live use structural visibility; Playwright uses rendered visibility.
    Without a count or field predicate, hidden and absent elements satisfy refutation.
    Counts and field predicates do not add a visibility requirement, matching native assertions.

    Supports `text:`, `count:`, one-based `at:`, `value:`, `checked:`, `selected:`,
    `label:`, `exact:`, and `timeout:`. Text and label matching default to substring
    matching. `exact: true` matches the complete normalized text or label and is
    case-sensitive. Value comparisons are exact; `selected:` matches a selected
    option's complete normalized text. With field predicates, `exact:` applies
    only to the optional label.

    Only one of `text:`, `value:`, `checked:`, or `selected:` is accepted. Counts
    cannot be combined with field predicates or `at:`. Label filtering precedes
    `at:`, which precedes text filtering. Value and checked predicates require
    one control. `exact:` requires `text:` or `label:`.

    The special selector `"title"` accepts `text:`, `exact:`, and `timeout:`.
    Text defaults to substring matching; without text it requires a nonempty title.
    """
    @spec unquote(name)(session(), String.t() | Locator.t()) :: session()
    @spec unquote(name)(session(), String.t() | Locator.t(), String.t() | keyword()) :: session()
    @spec unquote(name)(session(), String.t() | Locator.t(), String.t(), keyword()) :: session()
    def unquote(name)(session, selector), do: unquote(name)(session, selector, [])

    @doc group: "Assertions"
    @doc "Like `#{name}/2`, with options, or with `text` as a shorthand for the `text:` option."
    def unquote(name)(session, selector, options) when is_list(options) do
      expectation = has_expectation(session, selector, options)
      execute(session, expectation, unquote(negated?))
    end

    def unquote(name)(session, selector, text), do: unquote(name)(session, selector, text, [])

    @doc group: "Assertions"
    @doc "Like `#{name}/3` with `text`, plus `exact:`, `count:`, `at:` and `timeout:`."
    def unquote(name)(session, selector, text, options) do
      options = options!(options, [:exact, :count, :at, :timeout])
      unquote(name)(session, selector, Keyword.put(options, :text, text))
    end
  end

  @doc group: "Assertions"
  @doc """
  Checks a path, optionally with an exact flat `query_params:` map and `timeout:`.
  A whole `*` path segment matches one segment, including an empty segment.
  Other segments match literally. Query strings are ignored unless
  `query_params:` is supplied; fragments are always ignored.
  """
  @spec assert_path(session(), String.t(), keyword()) :: session()
  def assert_path(session, path, options \\ []), do: execute(session, path_expectation(path, options), false)

  @doc group: "Assertions"
  @doc "Negates the combined path and optional query expectation."
  @spec refute_path(session(), String.t(), keyword()) :: session()
  def refute_path(session, path, options \\ []), do: execute(session, path_expectation(path, options), true)

  defp role_locator(session, role, text) do
    string!(text, :text)
    locator_in_scope(session, Locator.by_role(role, name: text))
  end

  defp click_locator(session, locator), do: map_session(session, &Fluffy.click(&1, locator))

  defp click_text(session, selector, text, options) do
    {text_locator, label_locator} = text_and_label_locators(session, selector, text, options)
    locator = Locator.or_(text_locator, label_locator)
    map_session(session, &Fluffy.click(&1, locator))
  end

  # A CSS click target matched by its text, and the fallback matched by its label.
  defp text_and_label_locators(session, selector, text, options) do
    string!(text, :text)
    exact? = options |> options!([:exact]) |> Keyword.get(:exact, false)
    text_locator = session |> css_locator(selector) |> Locator.filter(has_text: text_matcher(text, exact?))
    {text_locator, field_locator(session, selector, text, exact: exact?)}
  end

  defp field_locator(session, selector, label, options) do
    string!(label, :label)
    label_locator = locator_in_scope(session, Locator.by_label(label, exact: Keyword.get(options, :exact, true)))

    if is_nil(selector), do: label_locator, else: Locator.and_(css_locator(session, selector), label_locator)
  end

  defp css_locator(session, selector) do
    string!(selector, :selector)
    locator_in_scope(session, Locator.by_css(selector))
  end

  defp locator_in_scope(%Session{scope: %Locator{} = scope}, locator), do: Locator.Internal.within(scope, locator)
  defp locator_in_scope(_session, locator), do: locator

  defp base_locator(selector) when is_binary(selector), do: Locator.by_css(selector)
  defp base_locator(%Locator{} = locator), do: locator

  defp base_locator(selector) do
    raise ArgumentError, "selector: must be a string or a Fluffy.Locator, got: #{inspect(selector)}"
  end

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

    locator = base_locator(selector)

    locator =
      if Keyword.has_key?(options, :label),
        do: Locator.and_(locator, Locator.by_label(options[:label], exact: Keyword.get(options, :exact, false))),
        else: locator

    locator = locator_in_scope(session, locator)
    locator = if options[:at], do: Locator.nth(locator, options[:at] - 1), else: locator

    locator =
      if Keyword.has_key?(options, :text),
        do: Locator.filter(locator, has_text: text_matcher(options[:text], Keyword.get(options, :exact, false))),
        else: locator

    element_expectation(locator, options)
  end

  defp element_expectation(locator, options) do
    timeout = Keyword.take(options, [:timeout])

    cond do
      Keyword.has_key?(options, :selected) ->
        locator
        |> Locator.by_css("option:checked")
        |> Locator.filter(has_text: text_matcher(options[:selected], true))
        |> Expect.to_have_count(0, timeout)
        |> Expect.not_()

      Keyword.has_key?(options, :value) ->
        Expect.to_have_value(locator, options[:value], timeout)

      Keyword.has_key?(options, :checked) ->
        Expect.to_be_checked(locator, Keyword.put(timeout, :checked, options[:checked]))

      Keyword.has_key?(options, :count) ->
        Expect.to_have_count(locator, options[:count], timeout)

      true ->
        locator |> Locator.filter(visible: true) |> Locator.first() |> Expect.to_be_visible(timeout)
    end
  end

  # `exact: true` matches the whole whitespace-normalized text, case-sensitively. Only JS
  # syntax characters are escaped: under the `u` flag JS rejects escapes such as `\-`.
  # Under `u`, Playwright also leaves quotes and `>>` unescaped in the selector, which
  # breaks it, so those characters are written as `\xNN` (valid in both JS and PCRE).
  defp text_matcher(text, false), do: text

  defp text_matcher(text, true) do
    words = text |> String.split(~r/\s+/u, trim: true) |> Enum.map_join("\\s+", &escape_regex/1)
    Regex.compile!("^\\s*#{words}\\s*$", "u")
  end

  defp escape_regex(text) do
    text
    |> String.replace(~r/[\\^$.*+?()[\]{}|]/, "\\\\\\0")
    |> String.replace(["'", "\"", "`", ">"], &("\\x" <> Base.encode16(&1)))
  end

  # PhoenixTest compares the path, with `*` matching one segment, and with
  # `query_params:` the complete decoded query.
  defp path_expectation(path, options) do
    string!(path, :path)
    options = options!(options, [:query_params, :timeout])
    parts = String.split(path, "/")
    query = if Keyword.has_key?(options, :query_params), do: options[:query_params] |> query_map!() |> Enum.sort()

    expected = fn %URI{} = uri ->
      path_parts_match?(parts, uri.path) and (is_nil(query) or query == decode_query(uri.query))
    end

    Expect.page_to_have_url(expected, Keyword.take(options, [:timeout]))
  end

  defp decode_query(nil), do: []
  defp decode_query(query), do: query |> URI.query_decoder() |> Enum.sort()

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

  defp validate_option!({:count, value}),
    do: reject!(not (is_integer(value) and value >= 0), "count: must be a nonnegative integer")

  defp validate_option!({:timeout, value}),
    do:
      reject!(
        not (value == :infinity or (is_integer(value) and value >= 0)),
        "timeout: must be a nonnegative integer or :infinity"
      )

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
