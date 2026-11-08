defmodule Fluffy.Options do
  @moduledoc false

  alias Fluffy.Options.Native

  @timeout_options [
    timeout: [
      type: :non_neg_integer,
      doc:
        "Maximum time in milliseconds to wait for the operation. Defaults to the session's `timeout:`. " <>
          "Playwright browser bookkeeping and navigation synchronization use the session timeout separately."
    ]
  ]

  @action_schema NimbleOptions.new!(@timeout_options)

  # The upstream call behind each cross-driver action and its options that pass through
  # on Playwright. Fluffy owns `timeout` (its retry budget); `no_wait_after` and `signal`
  # would bypass its navigation tracking.
  @native_actions [
    click:
      {PlaywrightEx.Locator, :click, 2,
       [:button, :click_count, :delay, :force, :modifiers, :position, :scroll, :steps, :trial]},
    fill: {PlaywrightEx.Locator, :fill, 3, [:force]},
    clear: {PlaywrightEx.Locator, :clear, 2, [:force]},
    set_checked: {PlaywrightEx.Locator, :set_checked, 3, [:force, :position, :scroll, :trial]},
    check: {PlaywrightEx.Locator, :check, 2, [:force, :position, :scroll, :trial]},
    uncheck: {PlaywrightEx.Locator, :uncheck, 2, [:force, :position, :scroll, :trial]},
    select_option: {PlaywrightEx.Locator, :select_option, 3, [:force]},
    press: {PlaywrightEx.Locator, :press, 3, [:delay]},
    set_input_files: {PlaywrightEx.Locator, :set_input_files, 3, []},
    reload: {PlaywrightEx.Page, :reload, 2, [:wait_until]}
  ]

  # Playwright-only actions, classified like the cross-driver ones.
  @playwright_actions [
    hover: {PlaywrightEx.Locator, :hover, 2, [:force, :modifiers, :position, :scroll, :trial]},
    drag_to: {PlaywrightEx.Locator, :drag_to, 3, [:force, :scroll, :source_position, :steps, :target_position, :trial]},
    press_sequentially: {PlaywrightEx.Locator, :press_sequentially, 3, [:delay]},
    focus: {PlaywrightEx.Locator, :focus, 2, []},
    blur: {PlaywrightEx.Locator, :blur, 2, []},
    dblclick:
      {PlaywrightEx.Locator, :dblclick, 2, [:button, :delay, :force, :modifiers, :position, :scroll, :steps, :trial]},
    tap: {PlaywrightEx.Locator, :tap, 2, [:force, :modifiers, :position, :scroll, :trial]},
    dispatch_event: {PlaywrightEx.Locator, :dispatch_event, 4, []},
    select_text: {PlaywrightEx.Locator, :select_text, 2, [:force]},
    scroll_into_view_if_needed: {PlaywrightEx.Locator, :scroll_into_view_if_needed, 2, []},
    locator_screenshot:
      {PlaywrightEx.Locator, :screenshot, 2,
       [:animations, :caret, :mask, :mask_color, :omit_background, :quality, :scale, :style, :type]},
    emulate_media:
      {PlaywrightEx.Page, :emulate_media, 2, [:color_scheme, :contrast, :forced_colors, :media, :reduced_motion]},
    keyboard_press: {PlaywrightEx.Keyboard, :press, 3, [:delay]},
    keyboard_type: {PlaywrightEx.Keyboard, :type, 3, [:delay]},
    mouse_click: {PlaywrightEx.Mouse, :click, 4, [:button, :click_count, :delay]},
    mouse_dblclick: {PlaywrightEx.Mouse, :dblclick, 4, [:button, :delay]},
    mouse_down: {PlaywrightEx.Mouse, :down, 2, [:button, :click_count]},
    mouse_up: {PlaywrightEx.Mouse, :up, 2, [:button, :click_count]},
    mouse_move: {PlaywrightEx.Mouse, :move, 4, [:steps]},
    go_back: {PlaywrightEx.Page, :go_back, 2, [:wait_until]},
    go_forward: {PlaywrightEx.Page, :go_forward, 2, [:wait_until]},
    install_clock: {PlaywrightEx.Clock, :install, 2, [:time]}
  ]

  @fluffy_native_keys [:timeout]
  # `path` is the positional argument of an element screenshot.
  @denied_native_keys [:no_wait_after, :signal, :path]

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

  @action_schemas Map.new(@native_actions ++ @playwright_actions, fn {action, {module, fun, arity, keys}} ->
                    native =
                      for {key, entry} <- Native.schema(module, fun, arity, keys) do
                        {key, Keyword.merge(entry, Keyword.get(@native_option_overrides, key, []))}
                      end

                    {action, NimbleOptions.new!(@timeout_options ++ native)}
                  end)

  # The upstream assertion behind each expectation and the options Fluffy mirrors on
  # every driver. No assertion option passes through to the browser.
  @native_expectations [
    to_have_count: {PlaywrightEx.Expect, :to_have_count, 3, []},
    to_be_visible: {PlaywrightEx.Expect, :to_be_visible, 2, [:visible]},
    to_be_disabled: {PlaywrightEx.Expect, :to_be_disabled, 2, []},
    to_be_editable: {PlaywrightEx.Expect, :to_be_editable, 2, [:editable]},
    to_be_enabled: {PlaywrightEx.Expect, :to_be_enabled, 2, [:enabled]},
    to_be_focused: {PlaywrightEx.Expect, :to_be_focused, 2, []},
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
    visible: [type: :boolean, doc: "Set to false to expect a hidden target, like `not_/1`."],
    editable: [type: :boolean, doc: "Set to false to expect a read-only target, like `not_/1`."],
    enabled: [type: :boolean, doc: "Set to false to expect a disabled target, like `not_/1`."],
    checked: [type: :boolean, doc: "Set to false to expect an unchecked control."],
    indeterminate: [type: :boolean, doc: "Expect the browser-owned indeterminate state."],
    ignore_case: [type: :boolean, doc: "Match a string or regular expression case-insensitively."],
    attached: [type: :boolean, doc: "Set to false to expect a detached target, like `not_/1`."],
    use_inner_text: [
      type: :boolean,
      doc: "*Playwright only.* Read the browser's rendered `innerText` instead of the text content."
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

  # Fluffy-owned locator options whose regular-expression form only Playwright matches.
  @playwright_regex_locator_keys [:name, :has_text, :has_not_text]

  @text_or_regex [
    type: {:or, [:string, {:struct, Regex}]},
    type_spec: quote(do: String.t() | Regex.t()),
    type_doc: "`t:String.t/0` | `t:Regex.t/0`"
  ]

  # Fluffy compiles locator selectors itself, so it validates what PlaywrightEx would.
  # Text options take a string or an Elixir regex, like `name:` and `has_text:`.
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

  {module, fun, arity, classes} = @native_locators[:by_role]

  @playwright_role_locator_options Native.schema(module, fun, arity, classes[:playwright], @playwright_locator_types)

  @playwright_locator_keys @native_locators
                           |> Enum.flat_map(fn {_, {_, _, _, classes}} -> Keyword.get(classes, :playwright, []) end)
                           |> Enum.uniq()

  @playwright_option_keys @native_actions |> Enum.flat_map(fn {_, {_, _, _, keys}} -> keys end) |> Enum.uniq()
  @expectation_schema NimbleOptions.new!(@timeout_options)

  @url_matcher_schema NimbleOptions.new!(
                        path: [
                          type: :string,
                          doc: "Serialized URL pathname to match exactly."
                        ],
                        query: [
                          type: {:map, :string, {:or, [:string, {:list, :string}]}},
                          type_spec: quote(do: %{String.t() => String.t() | [String.t()]}),
                          doc: "Decoded query names and their ordered value or values."
                        ],
                        query_mode: [
                          type: {:in, [:exact, :subset]},
                          default: :exact,
                          doc: "Require the complete query or allow unrelated parameter names."
                        ],
                        fragment: [
                          type: {:or, [nil, :string]},
                          type_spec: quote(do: String.t() | nil),
                          doc: "Serialized fragment without `#`; nil requires no fragment."
                        ]
                      )

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
                                     "A regular expression is *Playwright only.*"
                               ],
                           exact: [
                             type: :boolean,
                             doc: "Require an exact, case-sensitive accessible-name match."
                           ]
                         ] ++ @playwright_role_locator_options
                       )

  @test_id_locator_schema NimbleOptions.new!(
                            attribute: [
                              type: :string,
                              default: "data-testid",
                              doc: "Attribute used as the test-id source."
                            ]
                          )

  @filter_locator_schema NimbleOptions.new!(
                           visible: [
                             type: :boolean,
                             doc: "Filter by structural visibility in Static/Live and rendered visibility in Playwright."
                           ],
                           exact: [
                             type: :boolean,
                             doc: "Match the whole normalized text, case-sensitively, for has_text and has_not_text."
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
                                     "A regular expression is *Playwright only.*"
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
                                     "A regular expression is *Playwright only.*"
                               ]
                         )

  @setup_schema NimbleOptions.new!(
                  repos: [type: {:list, :atom}],
                  sandbox: [type: :boolean]
                )

  @session_schema NimbleOptions.new!(
                    endpoint: [type: :atom],
                    base_url: [type: :string],
                    headers: [type: {:list, {:tuple, [{:or, [:atom, :string]}, :string]}}],
                    conn: [type: {:struct, Plug.Conn}],
                    timeout: [type: :pos_integer],
                    browser_context: [type: :keyword_list]
                  )

  @playwright_schema NimbleOptions.new!(
                       enabled: [type: :boolean, default: true],
                       engine: [type: {:in, [:chromium, :firefox, :webkit]}, default: :chromium],
                       executable: [type: :string],
                       timeout: [type: :pos_integer, default: 15_000],
                       launch_options: [type: :keyword_list, default: []],
                       artifact_dir: [type: {:or, [nil, :string]}],
                       trace_dir: [type: :string, default: "traces"],
                       log_browser_console: [type: :boolean, default: true]
                     )

  @type setup_option :: unquote(NimbleOptions.option_typespec(@setup_schema))
  @type session_option :: unquote(NimbleOptions.option_typespec(@session_schema))
  @type playwright_option :: unquote(NimbleOptions.option_typespec(@playwright_schema))

  @doc false
  def setup_schema, do: @setup_schema

  @doc false
  def session_schema, do: @session_schema

  @doc false
  def playwright_schema, do: @playwright_schema

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

  @doc "Locator options whose regular-expression form only a browser can honor."
  def playwright_regex_locator_keys, do: @playwright_regex_locator_keys

  @doc false
  def native_expectations, do: @native_expectations

  @doc false
  def denied_expectation_keys, do: @denied_expectation_keys

  @doc false
  def expectation_schema(matcher), do: Map.fetch!(@expectation_schemas, matcher)

  @doc false
  def native_reference(action) do
    {module, fun, arity, _keys} = Keyword.fetch!(@native_actions ++ @playwright_actions, action)
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
  def url_matcher_schema, do: @url_matcher_schema

  @doc false
  def file_input_schema, do: @file_input_schema

  @doc false
  def exact_locator_schema, do: @exact_locator_schema

  @doc false
  def role_locator_schema, do: @role_locator_schema

  @doc false
  def test_id_locator_schema, do: @test_id_locator_schema

  @doc false
  def filter_locator_schema, do: @filter_locator_schema

  @spec validate_action!(keyword()) :: keyword()
  def validate_action!(options), do: NimbleOptions.validate!(options, @action_schema)

  @spec validate_action!(atom(), keyword()) :: keyword()
  def validate_action!(action, options), do: NimbleOptions.validate!(options, action_schema(action))

  @spec validate_expectation!(keyword()) :: keyword()
  def validate_expectation!(options), do: NimbleOptions.validate!(options, @expectation_schema)

  @spec validate_expectation!(atom(), keyword()) :: keyword()
  def validate_expectation!(matcher, options), do: NimbleOptions.validate!(options, expectation_schema(matcher))

  @spec validate_url_matcher!(keyword()) :: keyword()
  def validate_url_matcher!(options), do: NimbleOptions.validate!(options, @url_matcher_schema)

  @spec validate_file_input!(keyword()) :: keyword()
  def validate_file_input!(options), do: NimbleOptions.validate!(options, @file_input_schema)

  @spec validate_exact_locator!(keyword()) :: keyword()
  def validate_exact_locator!(options), do: NimbleOptions.validate!(options, @exact_locator_schema)

  @spec validate_role_locator!(keyword()) :: keyword()
  def validate_role_locator!(options), do: NimbleOptions.validate!(options, @role_locator_schema)

  @spec validate_test_id_locator!(keyword()) :: keyword()
  def validate_test_id_locator!(options), do: NimbleOptions.validate!(options, @test_id_locator_schema)

  @spec validate_filter_locator!(keyword()) :: keyword()
  def validate_filter_locator!(options), do: NimbleOptions.validate!(options, @filter_locator_schema)

  @spec validate_setup!(keyword()) :: keyword()
  def validate_setup!(options), do: NimbleOptions.validate!(options, @setup_schema)

  @spec validate_session!(atom(), keyword()) :: keyword()
  def validate_session!(backend, options) do
    options = NimbleOptions.validate!(options, @session_schema)

    cond do
      backend == :phoenix and Keyword.has_key?(options, :browser_context) ->
        raise ArgumentError, ":browser_context options are available only for Playwright sessions"

      backend == :playwright and Keyword.has_key?(options, :conn) ->
        raise ArgumentError, ":conn is available only for Phoenix sessions"

      true ->
        :ok
    end

    validate_conn!(options[:conn])

    options
  end

  @doc false
  # The `config :fluffy, :playwright` a session runs with, schema defaults included.
  @spec playwright_config() :: keyword()
  def playwright_config do
    case :fluffy |> Application.get_env(:playwright, false) |> validate_playwright!() do
      false -> NimbleOptions.validate!([], @playwright_schema)
      config -> config
    end
  end

  @spec validate_playwright!(false | keyword()) :: false | keyword()
  def validate_playwright!(false), do: false

  def validate_playwright!(options) when is_list(options), do: NimbleOptions.validate!(options, @playwright_schema)

  def validate_playwright!(other) do
    raise ArgumentError,
          "expected :fluffy, :playwright configuration to be false or a keyword list, got: #{inspect(other)}"
  end

  defp validate_conn!(nil), do: :ok

  defp validate_conn!(%Plug.Conn{state: :unset}), do: :ok

  defp validate_conn!(%Plug.Conn{state: state}) do
    raise ArgumentError,
          ":conn must be a fresh, unsent %Plug.Conn{} with state :unset, got: #{inspect(state)}"
  end
end
