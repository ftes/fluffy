defmodule Fluffy.Options do
  @moduledoc false

  alias Fluffy.Options.Native

  @timeout_options [
    timeout: [
      type: :timeout,
      doc:
        "Maximum time in milliseconds to wait for the operation. As in Playwright Test, defaults to " <>
          "the action timeout (navigations: the navigation timeout), no timeout unless set, " <>
          "and for assertions to the expect timeout, 5 seconds ([Timeouts](installation.md#timeouts)). " <>
          "`0` checks once, unlike Playwright, where `0` disables the timeout. Playwright actions and waits " <>
          "reject `0` with an `ArgumentError`, as they cannot check once; Playwright assertions accept it. " <>
          "`:infinity` disables the timeout: Playwright waits with no timeout, LiveView retries until the test " <>
          "times out, and Static, where nothing changes, checks once."
    ]
  ]

  @action_schema NimbleOptions.new!(@timeout_options)

  # Calls that, as in Playwright, have no timeout: they wait while a script blocks the page.
  @untimed_schema NimbleOptions.new!([])
  @untimed_actions [
    :content,
    :pdf,
    :emulate_media,
    :keyboard_press,
    :keyboard_type,
    :mouse_click,
    :mouse_dblclick,
    :mouse_down,
    :mouse_up,
    :mouse_move,
    :unroute_all,
    :install_clock
  ]

  # The upstream call behind each cross-driver action. Its options pass through on
  # Playwright, read from PlaywrightEx's `__options__/1`, except Fluffy's own `timeout`
  # (its retry budget) and the denied ones below.
  @native_actions [
    click: {PlaywrightEx.Locator, :click, 2},
    fill: {PlaywrightEx.Locator, :fill, 3},
    clear: {PlaywrightEx.Locator, :clear, 2},
    set_checked: {PlaywrightEx.Locator, :set_checked, 3},
    check: {PlaywrightEx.Locator, :check, 2},
    uncheck: {PlaywrightEx.Locator, :uncheck, 2},
    select_option: {PlaywrightEx.Locator, :select_option, 3},
    press: {PlaywrightEx.Locator, :press, 3},
    set_input_files: {PlaywrightEx.Locator, :set_input_files, 3},
    reload: {PlaywrightEx.Page, :reload, 2}
  ]

  # Playwright-only actions, whose options pass through the same way.
  @playwright_actions [
    hover: {PlaywrightEx.Locator, :hover, 2},
    drag_to: {PlaywrightEx.Locator, :drag_to, 3},
    press_sequentially: {PlaywrightEx.Locator, :press_sequentially, 3},
    focus: {PlaywrightEx.Locator, :focus, 2},
    blur: {PlaywrightEx.Locator, :blur, 2},
    dblclick: {PlaywrightEx.Locator, :dblclick, 2},
    tap: {PlaywrightEx.Locator, :tap, 2},
    dispatch_event: {PlaywrightEx.Locator, :dispatch_event, 4},
    select_text: {PlaywrightEx.Locator, :select_text, 2},
    scroll_into_view_if_needed: {PlaywrightEx.Locator, :scroll_into_view_if_needed, 2},
    wait_for: {PlaywrightEx.Locator, :wait_for, 2},
    bounding_box: {PlaywrightEx.Locator, :bounding_box, 2},
    aria_snapshot: {PlaywrightEx.Locator, :aria_snapshot, 2},
    drop: {PlaywrightEx.Locator, :drop, 3},
    locator_evaluate: {PlaywrightEx.Locator, :evaluate, 4},
    locator_wait_for_function: {PlaywrightEx.Locator, :wait_for_function, 4},
    page_aria_snapshot: {PlaywrightEx.Page, :aria_snapshot, 2},
    wait_for_function: {PlaywrightEx.Page, :wait_for_function, 4},
    wait_for_load_state: {PlaywrightEx.Page, :wait_for_load_state, 3},
    unroute_all: {PlaywrightEx.BrowserContext, :unroute_all, 2},
    locator_screenshot: {PlaywrightEx.Locator, :screenshot, 2},
    page_screenshot: {PlaywrightEx.Page, :screenshot, 2},
    to_have_screenshot: {PlaywrightEx.Expect, :to_have_screenshot, 2},
    content: {PlaywrightEx.Page, :content, 2},
    pdf: {PlaywrightEx.Page, :pdf, 2},
    emulate_media: {PlaywrightEx.Page, :emulate_media, 2},
    keyboard_press: {PlaywrightEx.Keyboard, :press, 3},
    keyboard_type: {PlaywrightEx.Keyboard, :type, 3},
    mouse_click: {PlaywrightEx.Mouse, :click, 4},
    mouse_dblclick: {PlaywrightEx.Mouse, :dblclick, 4},
    mouse_down: {PlaywrightEx.Mouse, :down, 2},
    mouse_up: {PlaywrightEx.Mouse, :up, 2},
    mouse_move: {PlaywrightEx.Mouse, :move, 4},
    go_back: {PlaywrightEx.Page, :go_back, 2},
    go_forward: {PlaywrightEx.Page, :go_forward, 2},
    install_clock: {PlaywrightEx.Clock, :install, 2}
  ]

  @fluffy_native_keys [:timeout]
  @denied_native_keys [:no_wait_after, :signal]

  # Upstream docs and types of a passed-through option that Fluffy's behavior completes.
  @native_option_overrides [
    wait_until: [
      doc:
        "*Playwright only.* When Playwright considers the navigation done: `:commit`, `:domcontentloaded`, " <>
          "`:load` (the default) or `:networkidle`. Fluffy then still waits until the document is parsed " <>
          "and its LiveViews are connected, as after every navigation."
    ],
    mask: [
      type_spec: quote(do: [Fluffy.Locator.t()]),
      type_doc: "list of `t:Fluffy.Locator.t/0`",
      doc: "*Playwright only.* Locators of the elements to cover with a box of `:mask_color` in the screenshot."
    ]
  ]

  # These replace the upstream option of the same name: a baseline's `path:`, which
  # PlaywrightEx requires outside a `PlaywrightEx.Test` test.
  @required_action_options [
    to_have_screenshot: [
      path: [
        type: :string,
        doc:
          "*Playwright only.* The baseline image, a `.png` or `.webp` file, resolved against the current " <>
            "working directory, in place of `:name`. Required in a module without `use PlaywrightEx.Test`."
      ]
    ]
  ]

  # `path:` of a script or style tag is the file to inject, not a file to write, so these
  # are not classified with the upstream options above.
  @tag_options [
    content: [type: :string, doc: "Raw source to inject."],
    path: [type: :string, doc: "File to inject, resolved against the current working directory."],
    url: [type: :string, doc: "URL to load."]
  ]

  @action_schemas @native_actions
                  |> Kernel.++(@playwright_actions)
                  |> Map.new(fn {action, {module, fun, _arity}} ->
                    required = Keyword.get(@required_action_options, action, [])
                    excluded = @fluffy_native_keys ++ @denied_native_keys ++ Keyword.keys(required)

                    native =
                      for {key, entry} <- Native.schema(module, fun, excluded) do
                        {key, Keyword.merge(entry, Keyword.get(@native_option_overrides, key, []))}
                      end

                    timeout = if action in @untimed_actions, do: [], else: @timeout_options
                    {action, NimbleOptions.new!(timeout ++ required ++ native)}
                  end)
                  |> Map.merge(%{
                    add_script_tag:
                      NimbleOptions.new!(@tag_options ++ [type: [type: :string, doc: "Script type, such as `module`."]]),
                    add_style_tag: NimbleOptions.new!(@tag_options)
                  })

  # The upstream assertion behind each expectation and the options Fluffy mirrors on
  # every driver. No assertion option passes through to the browser.
  @native_expectations [
    to_have_count: {PlaywrightEx.Expect, :to_have_count, 3, []},
    to_be_visible: {PlaywrightEx.Expect, :to_be_visible, 2, [:visible]},
    to_be_disabled: {PlaywrightEx.Expect, :to_be_disabled, 2, []},
    to_be_editable: {PlaywrightEx.Expect, :to_be_editable, 2, [:editable]},
    to_be_enabled: {PlaywrightEx.Expect, :to_be_enabled, 2, [:enabled]},
    to_be_focused: {PlaywrightEx.Expect, :to_be_focused, 2, []},
    to_be_in_viewport: {PlaywrightEx.Expect, :to_be_in_viewport, 2, [:ratio]},
    to_have_css: {PlaywrightEx.Expect, :to_have_css, 4, [:pseudo]},
    to_have_js_property: {PlaywrightEx.Expect, :to_have_js_property, 4, []},
    to_have_role: {PlaywrightEx.Expect, :to_have_role, 3, []},
    to_have_accessible_name: {PlaywrightEx.Expect, :to_have_accessible_name, 3, [:ignore_case]},
    to_have_accessible_description: {PlaywrightEx.Expect, :to_have_accessible_description, 3, [:ignore_case]},
    to_have_accessible_error_message: {PlaywrightEx.Expect, :to_have_accessible_error_message, 3, [:ignore_case]},
    to_match_aria_snapshot: {PlaywrightEx.Expect, :to_match_aria_snapshot, 3, [:name, :path]},
    to_be_checked: {PlaywrightEx.Expect, :to_be_checked, 2, [:checked, :indeterminate]},
    to_have_value: {PlaywrightEx.Expect, :to_have_value, 3, []},
    to_have_values: {PlaywrightEx.Expect, :to_have_values, 3, []},
    to_have_text: {PlaywrightEx.Expect, :to_have_text, 3, [:ignore_case, :use_inner_text]},
    to_contain_text: {PlaywrightEx.Expect, :to_contain_text, 3, [:ignore_case, :use_inner_text]},
    to_have_attribute: {PlaywrightEx.Expect, :to_have_attribute, 4, [:ignore_case]},
    to_have_class: {PlaywrightEx.Expect, :to_have_class, 3, []},
    to_contain_class: {PlaywrightEx.Expect, :to_contain_class, 3, []},
    to_have_id: {PlaywrightEx.Expect, :to_have_id, 3, []},
    to_be_attached: {PlaywrightEx.Expect, :to_be_attached, 2, [:attached]},
    to_be_hidden: {PlaywrightEx.Expect, :to_be_hidden, 2, []},
    to_be_empty: {PlaywrightEx.Expect, :to_be_empty, 2, []},
    page_to_have_title: {PlaywrightEx.Expect, :to_have_title, 3, []},
    page_to_have_url: {PlaywrightEx.Expect, :to_have_url, 3, [:ignore_case]}
  ]

  @denied_expectation_keys [:signal]

  @mirrored_expectation_options [
    path: [
      type: :string,
      doc:
        "The snapshot file, in place of `expected`, resolved against the current working directory. " <>
          "Fluffy does not derive a path from the test name."
    ],
    visible: [type: :boolean, doc: "Set to false to expect a hidden target, like `not_/1`."],
    editable: [type: :boolean, doc: "Set to false to expect a read-only target, like `not_/1`."],
    enabled: [type: :boolean, doc: "Set to false to expect a disabled target, like `not_/1`."],
    checked: [type: :boolean, doc: "Set to false to expect an unchecked control."],
    indeterminate: [type: :boolean, doc: "Expect the browser-owned indeterminate state."],
    ignore_case: [type: :boolean, doc: "Match a string or regular expression case-insensitively."],
    attached: [type: :boolean, doc: "Set to false to expect a detached target, like `not_/1`."],
    ratio: [
      type: {:or, [:integer, :float]},
      doc: "The minimal share of the target that must intersect the viewport, from 0 to 1."
    ],
    use_inner_text: [
      type: :boolean,
      doc: "*Playwright only.* Read the browser's rendered `innerText` instead of the text content."
    ],
    pseudo: [
      type: {:in, [:before, :after]},
      doc: "*Playwright only.* The pseudo-element to read computed styles from."
    ]
  ]

  @expectation_schemas Map.new(@native_expectations, fn {matcher, {_module, _fun, _arity, mirrored}} ->
                         mirrored = Keyword.take(@mirrored_expectation_options, mirrored)
                         {matcher, NimbleOptions.new!(@timeout_options ++ mirrored)}
                       end)

  # The upstream factory behind each locator constructor and how Fluffy covers its
  # options: `fluffy` ones work on every driver, `playwright` ones compile into the
  # Playwright selector and raise on Phoenix, and `denied` ones have a Fluffy
  # replacement. `by_css` takes no options; chain `filter/2` instead.
  @native_locators [
    by_role:
      {PlaywrightEx.Locator, :get_by_role, 3,
       fluffy: [:exact, :name],
       playwright: [:checked, :description, :disabled, :expanded, :include_hidden, :level, :pressed, :selected]},
    by_text: {PlaywrightEx.Locator, :get_by_text, 3, fluffy: [:exact]},
    by_label: {PlaywrightEx.Locator, :get_by_label, 3, fluffy: [:exact]},
    by_placeholder: {PlaywrightEx.Locator, :get_by_placeholder, 3, fluffy: [:exact]},
    by_alt_text: {PlaywrightEx.Locator, :get_by_alt_text, 3, fluffy: [:exact]},
    by_title: {PlaywrightEx.Locator, :get_by_title, 3, fluffy: [:exact]},
    by_test_id: {PlaywrightEx.Locator, :get_by_test_id, 2, []},
    by_css: {PlaywrightEx.Locator, :locator, 3, denied: [:has, :has_not, :has_not_text, :has_text]},
    filter: {PlaywrightEx.Locator, :filter, 2, fluffy: [:has, :has_not, :has_not_text, :has_text, :visible]}
  ]

  @text_or_regex [
    type: {:custom, __MODULE__, :text_or_reg_exp, []},
    type_spec: quote(do: String.t() | Regex.t() | PlaywrightEx.RegExp.t()),
    type_doc: "`t:String.t/0` | `t:Regex.t/0` | `t:PlaywrightEx.RegExp.t/0`"
  ]

  # Fluffy compiles locator selectors itself, so it validates what PlaywrightEx would.
  # Text options take a string or a regex, like `name:` and `has_text:`.
  @playwright_locator_types [
    checked: :boolean,
    description: @text_or_regex,
    disabled: :boolean,
    expanded: :boolean,
    include_hidden: :boolean,
    level: :integer,
    pressed: :boolean,
    selected: :boolean
  ]

  {module, fun, _arity, classes} = @native_locators[:by_role]

  @playwright_role_locator_options Native.schema(module, fun, classes[:playwright], @playwright_locator_types)

  @playwright_locator_keys @native_locators
                           |> Enum.flat_map(fn {_, {_, _, _, classes}} -> Keyword.get(classes, :playwright, []) end)
                           |> Enum.uniq()

  @playwright_option_keys @native_actions
                          |> Enum.flat_map(fn {_, {module, fun, _}} ->
                            Native.keys(module, fun, @fluffy_native_keys ++ @denied_native_keys)
                          end)
                          |> Enum.uniq()
  @expectation_schema NimbleOptions.new!(@timeout_options)

  @file_input_schema NimbleOptions.new!(
                       @timeout_options ++
                         [
                           max_bytes: [
                             type: :non_neg_integer,
                             doc: "Maximum aggregate size of the selected files in bytes."
                           ]
                         ]
                     )

  @exact_locator_schema NimbleOptions.new!(
                          exact: [
                            type: :boolean,
                            doc: "Require an exact, case-sensitive match."
                          ]
                        )

  @role_locator_schema NimbleOptions.new!(
                         [
                           name:
                             @text_or_regex ++
                               [
                                 doc:
                                   "Restrict the role locator by accessible name. " <>
                                     "A regular expression is tested against the normalized name."
                               ],
                           exact: [
                             type: :boolean,
                             doc: "Require an exact, case-sensitive accessible-name match."
                           ]
                         ] ++ @playwright_role_locator_options
                       )

  @filter_locator_schema NimbleOptions.new!(
                           visible: [
                             type: :boolean,
                             doc: "Filter by structural visibility in Static/Live and rendered visibility in Playwright."
                           ],
                           has: [
                             type: {:struct, Fluffy.Locator},
                             type_spec: quote(do: Fluffy.Locator.t()),
                             doc: "Keep elements containing a match for this locator."
                           ],
                           has_text:
                             @text_or_regex ++
                               [
                                 doc:
                                   "Keep elements containing this normalized text. " <>
                                     "A regular expression is tested against the raw text."
                               ],
                           has_not: [
                             type: {:struct, Fluffy.Locator},
                             type_spec: quote(do: Fluffy.Locator.t()),
                             doc: "Keep elements containing no match for this locator."
                           ],
                           has_not_text:
                             @text_or_regex ++
                               [
                                 doc:
                                   "Keep elements that do not contain this normalized text. " <>
                                     "A regular expression is tested against the raw text."
                               ]
                         )

  @session_schema NimbleOptions.new!(
                    endpoint: [type: :atom],
                    base_url: [type: :string],
                    headers: [type: {:list, {:tuple, [{:or, [:atom, :string]}, :string]}}],
                    conn: [type: {:struct, Plug.Conn}],
                    browser_context: [type: :keyword_list],
                    browser: [
                      type: {:struct, PlaywrightEx.Browser},
                      doc:
                        "*Playwright only.* The `PlaywrightEx.Browser` the session's context is created in. " <>
                          "Defaults to the test's browser from `PlaywrightEx.Test.BrowserPool.browser/1`; " <>
                          "to override launch options such as `headless: false` for one test, " <>
                          "pass `PlaywrightEx.Test.BrowserPool.browser(launch_options: ...)` " <>
                          "([Playwright setup](installation.md#playwright-setup))."
                    ]
                  )

  # `config :fluffy`. Playwright Test's `actionTimeout`, `expect.timeout` and `testIdAttribute`
  # are for Fluffy's sessions, over PlaywrightEx's (`config!/1`); no defaults: unset,
  # PlaywrightEx's apply.
  @config_schema NimbleOptions.new!(
                   action_timeout: [type: {:custom, __MODULE__, :default_timeout, []}],
                   # `0`: assertions check once, as with a call's `timeout: 0`.
                   expect_timeout: [type: :timeout],
                   test_id_attribute: [type: {:custom, __MODULE__, :test_id_attribute, []}],
                   base_url: [type: :string],
                   endpoint: [type: :atom],
                   ecto_repos: [type: {:list, :atom}],
                   file_input_max_bytes: [type: :pos_integer]
                 )

  @playwright_test_keys [:action_timeout, :expect_timeout, :test_id_attribute]

  @type session_option :: unquote(NimbleOptions.option_typespec(@session_schema))

  @doc false
  # A string or a regex; a `Regex` becomes its `PlaywrightEx.RegExp`, raising on PCRE-only syntax.
  def text_or_reg_exp(value) when is_binary(value) or is_struct(value, PlaywrightEx.RegExp), do: {:ok, value}
  def text_or_reg_exp(%Regex{} = value), do: {:ok, PlaywrightEx.RegExp.new(value)}
  def text_or_reg_exp(value), do: {:error, "expected a string or a regex, got: #{inspect(value)}"}

  @doc false
  def session_schema, do: @session_schema

  @doc false
  def action_schema, do: @action_schema

  @doc false
  def action_schema(action), do: Map.fetch!(@action_schemas, action)

  @doc false
  def native_actions, do: @native_actions

  @doc false
  def playwright_actions, do: @playwright_actions

  @doc false
  def native_locators, do: @native_locators

  @doc "Locator options that only a browser can honor."
  def playwright_locator_keys, do: @playwright_locator_keys

  @doc false
  def native_expectations, do: @native_expectations

  @doc false
  def denied_expectation_keys, do: @denied_expectation_keys

  @doc false
  def expectation_schema(matcher), do: Map.fetch!(@expectation_schemas, matcher)

  @doc false
  def native_reference(action) do
    {module, fun, arity} = Keyword.fetch!(@native_actions ++ @playwright_actions, action)
    Native.reference(module, fun, arity)
  end

  @doc false
  def fluffy_native_keys, do: @fluffy_native_keys

  @doc false
  def denied_native_keys, do: @denied_native_keys

  @doc "Options that only a browser can honor."
  def playwright_option_keys, do: @playwright_option_keys

  @doc false
  def expectation_schema, do: @expectation_schema

  @doc false
  def file_input_schema, do: @file_input_schema

  @doc false
  def exact_locator_schema, do: @exact_locator_schema

  @doc false
  def role_locator_schema, do: @role_locator_schema

  @doc false
  def filter_locator_schema, do: @filter_locator_schema

  @spec validate_action!(keyword()) :: keyword()
  def validate_action!(options), do: NimbleOptions.validate!(options, @action_schema)

  @spec validate_action!(atom(), keyword()) :: keyword()
  def validate_action!(action, options), do: NimbleOptions.validate!(options, action_schema(action))

  @doc "Validates the options of a call that, as in Playwright, takes none."
  @spec validate_untimed!(keyword()) :: keyword()
  def validate_untimed!(options), do: NimbleOptions.validate!(options, @untimed_schema)

  @spec split_action!(atom(), keyword()) :: {keyword(), keyword()}
  def split_action!(action, options), do: Keyword.split(validate_action!(action, options), [:timeout])

  @spec validate_expectation!(keyword()) :: keyword()
  def validate_expectation!(options), do: NimbleOptions.validate!(options, @expectation_schema)

  @spec validate_expectation!(atom(), keyword()) :: keyword()
  def validate_expectation!(matcher, options), do: NimbleOptions.validate!(options, expectation_schema(matcher))

  @doc "Splits an expectation's validated `timeout:` from the options that select how it matches."
  @spec split_expectation!(atom(), keyword()) :: {keyword(), keyword()}
  def split_expectation!(matcher, options), do: Keyword.split(validate_expectation!(matcher, options), [:timeout])

  @spec validate_file_input!(keyword()) :: keyword()
  def validate_file_input!(options), do: NimbleOptions.validate!(options, @file_input_schema)

  @spec validate_exact_locator!(keyword()) :: keyword()
  def validate_exact_locator!(options), do: NimbleOptions.validate!(options, @exact_locator_schema)

  @spec validate_role_locator!(keyword()) :: keyword()
  def validate_role_locator!(options), do: NimbleOptions.validate!(options, @role_locator_schema)

  @spec validate_filter_locator!(keyword()) :: keyword()
  def validate_filter_locator!(options), do: NimbleOptions.validate!(options, @filter_locator_schema)

  @spec validate_session!(atom(), keyword()) :: keyword()
  def validate_session!(backend, options) do
    options = NimbleOptions.validate!(options, @session_schema)

    cond do
      backend == :phoenix and Keyword.has_key?(options, :browser_context) ->
        raise ArgumentError, ":browser_context options are available only for Playwright sessions"

      backend == :phoenix and Keyword.has_key?(options, :browser) ->
        raise ArgumentError, ":browser is available only for Playwright sessions"

      backend == :playwright and Keyword.has_key?(options, :conn) ->
        raise ArgumentError, ":conn is available only for Phoenix sessions"

      true ->
        :ok
    end

    validate_conn!(options[:conn])

    options
  end

  @doc false
  # The setting `key`: Fluffy's of `@config_schema` if set, else PlaywrightEx's resolved one
  # (`PlaywrightEx.Test.config/0`, its defaults filled in), where `0` means no limit:
  # `:infinity` here. `navigation_timeout` is PlaywrightEx's only.
  @spec config!(atom()) :: term()
  def config!(key) when key in @playwright_test_keys do
    case Keyword.fetch(config!(), key) do
      {:ok, value} -> value
      :error -> playwright_ex_config(key)
    end
  end

  def config!(:navigation_timeout), do: playwright_ex_config(:navigation_timeout)

  defp playwright_ex_config(:expect_timeout), do: no_limit(PlaywrightEx.Test.config().expect.timeout)
  defp playwright_ex_config(:test_id_attribute), do: PlaywrightEx.Test.config().test_id_attribute
  defp playwright_ex_config(key), do: no_limit(Map.fetch!(PlaywrightEx.Test.config(), key))

  defp no_limit(0), do: :infinity
  defp no_limit(timeout), do: timeout

  @doc false
  # `config :fluffy`, validated: a misspelt or removed key raises, as kept it would silently
  # do nothing. A module's config (`config :fluffy, Fluffy.Sandbox, ...`) is validated by the
  # module, which has to exist.
  @spec config!() :: keyword()
  def config! do
    reject_removed_config!()
    {modules, options} = Enum.split_with(Application.get_all_env(:fluffy), &module_key?/1)

    for {module, _config} <- modules, !Code.ensure_loaded?(module) do
      raise ArgumentError, "invalid config :fluffy, #{inspect(module)}: no such module"
    end

    case NimbleOptions.validate(options, @config_schema) do
      {:ok, config} -> config
      {:error, error} -> raise ArgumentError, "invalid config :fluffy: " <> Exception.message(error)
    end
  end

  defp module_key?({key, _value}), do: match?("Elixir." <> _, Atom.to_string(key))

  @removed_config [
    timeout: "set `config :fluffy, expect_timeout: ...` for assertions and `action_timeout: ...` for actions",
    playwright:
      "set `config :fluffy, action_timeout: ..., expect_timeout: ...` and " <>
        "`config :playwright_ex, :test, navigation_timeout: ...` instead of `playwright: [timeout: ...]`",
    navigation_timeout:
      "set `config :playwright_ex, :test, navigation_timeout: ...`: only browser navigations wait, " <>
        "Phoenix navigations are synchronous"
  ]

  defp reject_removed_config! do
    for {key, hint} <- @removed_config, Application.fetch_env(:fluffy, key) != :error do
      raise ArgumentError, "config :fluffy, #{key}: is removed: as in Playwright Test, #{hint}"
    end

    :ok
  end

  @doc false
  # Playwright actions and navigations can't check once, so a default of `0` could only fail
  # them; Playwright's no limit is `:infinity` here.
  def default_timeout(timeout) when timeout == :infinity or (is_integer(timeout) and timeout > 0), do: {:ok, timeout}

  def default_timeout(0),
    do:
      {:error,
       "expected a positive integer or :infinity, got: 0. As Playwright actions and navigations " <>
         "cannot check once, 0 is no default; for no limit, use :infinity"}

  def default_timeout(timeout), do: {:error, "expected a positive integer or :infinity, got: #{inspect(timeout)}"}

  @doc false
  # As PlaywrightEx.Test's `test_id_attribute`: one attribute or a comma-separated list.
  def test_id_attribute(name) when is_binary(name) and name != "", do: {:ok, name}
  def test_id_attribute(name), do: {:error, "expected a non-empty string, got: #{inspect(name)}"}

  defp validate_conn!(nil), do: :ok

  defp validate_conn!(%Plug.Conn{state: :unset}), do: :ok

  defp validate_conn!(%Plug.Conn{state: state}) do
    raise ArgumentError,
          ":conn must be a fresh, unsent %Plug.Conn{} with state :unset, got: #{inspect(state)}"
  end
end
