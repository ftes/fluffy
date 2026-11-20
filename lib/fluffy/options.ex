defmodule Fluffy.Options do
  @moduledoc false

  alias Fluffy.Options.Native

  @timeout_options [
    timeout: [
      type: :timeout,
      doc:
        "Maximum time in milliseconds to wait for the operation. On a browser, as in Playwright Test, " <>
          "defaults to the action timeout (navigations: the navigation timeout), no timeout unless set, " <>
          "and for assertions to the expect timeout, 5 seconds; on Phoenix, to `phoenix_backend_timeout` " <>
          "([Configuration](installation.md#configuration)). " <>
          "`0` checks once, unlike Playwright, where `0` disables the timeout. Playwright actions and waits " <>
          "reject `0` with an `ArgumentError`, as they cannot check once; so do screenshot assertions, which " <>
          "take each screenshot within the timeout, while other Playwright assertions accept it. " <>
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
  # Playwright, read from Playwright's `__options__/1`, except Fluffy's own `timeout`
  # (its retry budget) and the denied ones below.
  @native_actions [
    click: {Playwright.Locator, :click, 2},
    fill: {Playwright.Locator, :fill, 3},
    clear: {Playwright.Locator, :clear, 2},
    set_checked: {Playwright.Locator, :set_checked, 3},
    check: {Playwright.Locator, :check, 2},
    uncheck: {Playwright.Locator, :uncheck, 2},
    select_option: {Playwright.Locator, :select_option, 3},
    press: {Playwright.Locator, :press, 3},
    set_input_files: {Playwright.Locator, :set_input_files, 3},
    reload: {Playwright.Page, :reload, 2}
  ]

  # Playwright-only actions, whose options pass through the same way.
  @playwright_actions [
    hover: {Playwright.Locator, :hover, 2},
    drag_to: {Playwright.Locator, :drag_to, 3},
    press_sequentially: {Playwright.Locator, :press_sequentially, 3},
    focus: {Playwright.Locator, :focus, 2},
    blur: {Playwright.Locator, :blur, 2},
    dblclick: {Playwright.Locator, :dblclick, 2},
    tap: {Playwright.Locator, :tap, 2},
    dispatch_event: {Playwright.Locator, :dispatch_event, 4},
    select_text: {Playwright.Locator, :select_text, 2},
    scroll_into_view_if_needed: {Playwright.Locator, :scroll_into_view_if_needed, 2},
    wait_for: {Playwright.Locator, :wait_for, 2},
    bounding_box: {Playwright.Locator, :bounding_box, 2},
    aria_snapshot: {Playwright.Locator, :aria_snapshot, 2},
    drop: {Playwright.Locator, :drop, 3},
    locator_evaluate: {Playwright.Locator, :evaluate, 4},
    locator_wait_for_function: {Playwright.Locator, :wait_for_function, 4},
    page_aria_snapshot: {Playwright.Page, :aria_snapshot, 2},
    wait_for_function: {Playwright.Page, :wait_for_function, 4},
    wait_for_load_state: {Playwright.Page, :wait_for_load_state, 3},
    unroute_all: {Playwright.BrowserContext, :unroute_all, 2},
    locator_screenshot: {Playwright.Locator, :screenshot, 2},
    page_screenshot: {Playwright.Page, :screenshot, 2},
    to_have_screenshot: {Playwright.Expect, :to_have_screenshot, 2},
    content: {Playwright.Page, :content, 2},
    pdf: {Playwright.Page, :pdf, 2},
    emulate_media: {Playwright.Page, :emulate_media, 2},
    keyboard_press: {Playwright.Keyboard, :press, 3},
    keyboard_type: {Playwright.Keyboard, :type, 3},
    mouse_click: {Playwright.Mouse, :click, 4},
    mouse_dblclick: {Playwright.Mouse, :dblclick, 4},
    mouse_down: {Playwright.Mouse, :down, 2},
    mouse_up: {Playwright.Mouse, :up, 2},
    mouse_move: {Playwright.Mouse, :move, 4},
    go_back: {Playwright.Page, :go_back, 2},
    go_forward: {Playwright.Page, :go_forward, 2},
    install_clock: {Playwright.Clock, :install, 2}
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
  # Playwright requires outside a `Playwright.Test` test.
  @required_action_options [
    to_have_screenshot: [
      path: [
        type: :string,
        doc:
          "*Playwright only.* The baseline image, a `.png` or `.webp` file, resolved against the current " <>
            "working directory, in place of `:name`."
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
    to_have_count: {Playwright.Expect, :to_have_count, 3, []},
    to_be_visible: {Playwright.Expect, :to_be_visible, 2, [:visible]},
    to_be_disabled: {Playwright.Expect, :to_be_disabled, 2, []},
    to_be_editable: {Playwright.Expect, :to_be_editable, 2, [:editable]},
    to_be_enabled: {Playwright.Expect, :to_be_enabled, 2, [:enabled]},
    to_be_focused: {Playwright.Expect, :to_be_focused, 2, []},
    to_be_in_viewport: {Playwright.Expect, :to_be_in_viewport, 2, [:ratio]},
    to_have_css: {Playwright.Expect, :to_have_css, 4, [:pseudo]},
    to_have_js_property: {Playwright.Expect, :to_have_js_property, 4, []},
    to_have_role: {Playwright.Expect, :to_have_role, 3, []},
    to_have_accessible_name: {Playwright.Expect, :to_have_accessible_name, 3, [:ignore_case]},
    to_have_accessible_description: {Playwright.Expect, :to_have_accessible_description, 3, [:ignore_case]},
    to_have_accessible_error_message: {Playwright.Expect, :to_have_accessible_error_message, 3, [:ignore_case]},
    to_match_aria_snapshot: {Playwright.Expect, :to_match_aria_snapshot, 3, [:name, :path]},
    to_be_checked: {Playwright.Expect, :to_be_checked, 2, [:checked, :indeterminate]},
    to_have_value: {Playwright.Expect, :to_have_value, 3, []},
    to_have_values: {Playwright.Expect, :to_have_values, 3, []},
    to_have_text: {Playwright.Expect, :to_have_text, 3, [:ignore_case, :use_inner_text]},
    to_contain_text: {Playwright.Expect, :to_contain_text, 3, [:ignore_case, :use_inner_text]},
    to_have_attribute: {Playwright.Expect, :to_have_attribute, 4, [:ignore_case]},
    to_have_class: {Playwright.Expect, :to_have_class, 3, []},
    to_contain_class: {Playwright.Expect, :to_contain_class, 3, []},
    to_have_id: {Playwright.Expect, :to_have_id, 3, []},
    to_be_attached: {Playwright.Expect, :to_be_attached, 2, [:attached]},
    to_be_hidden: {Playwright.Expect, :to_be_hidden, 2, []},
    to_be_empty: {Playwright.Expect, :to_be_empty, 2, []},
    page_to_have_title: {Playwright.Expect, :to_have_title, 3, []},
    page_to_have_url: {Playwright.Expect, :to_have_url, 3, [:ignore_case]}
  ]

  @denied_expectation_keys [:signal]

  @mirrored_expectation_options [
    name: [
      type: :string,
      doc: "The snapshot file's name, in place of `expected`, resolved by `Playwright.Test`."
    ],
    path: [
      type: :string,
      doc:
        "The snapshot file, in place of `expected`, resolved against the current working directory, " <>
          "in place of `:name`."
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
      {Playwright.Locator, :get_by_role, 3,
       fluffy: [:exact, :name],
       playwright: [:checked, :description, :disabled, :expanded, :include_hidden, :level, :pressed, :selected]},
    by_text: {Playwright.Locator, :get_by_text, 3, fluffy: [:exact]},
    by_label: {Playwright.Locator, :get_by_label, 3, fluffy: [:exact]},
    by_placeholder: {Playwright.Locator, :get_by_placeholder, 3, fluffy: [:exact]},
    by_alt_text: {Playwright.Locator, :get_by_alt_text, 3, fluffy: [:exact]},
    by_title: {Playwright.Locator, :get_by_title, 3, fluffy: [:exact]},
    by_test_id: {Playwright.Locator, :get_by_test_id, 2, []},
    by_css: {Playwright.Locator, :locator, 3, denied: [:has, :has_not, :has_not_text, :has_text]},
    filter: {Playwright.Locator, :filter, 2, fluffy: [:has, :has_not, :has_not_text, :has_text, :visible]}
  ]

  @text_or_regex [
    type: {:custom, __MODULE__, :text_or_reg_exp, []},
    type_spec: quote(do: String.t() | Regex.t() | Playwright.RegExp.t()),
    type_doc: "`t:String.t/0` | `t:Regex.t/0` | `t:Playwright.RegExp.t/0`"
  ]

  # Fluffy compiles locator selectors itself, so it validates what Playwright would.
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

  # A Phoenix session's `clear_cookies/2` filters; the browser's Playwright client validates its own.
  @clear_cookies_schema NimbleOptions.new!(for key <- [:domain, :name, :path], do: {key, @text_or_regex})

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
                    endpoint: [
                      type: :atom,
                      doc:
                        "The Phoenix endpoint, over `config :fluffy, endpoint:`, that a Phoenix session " <>
                          "dispatches to and the base URL defaults to ([Configuration](installation.md#configuration))."
                    ],
                    base_url: [
                      type: :string,
                      doc: "The session's base URL ([Configuration](installation.md#configuration))."
                    ],
                    extra_http_headers: [
                      type: {:map, :string, :string},
                      doc:
                        "Headers sent with every request, replacing the test's `extra_http_headers` as a whole, " <>
                          "as in Playwright."
                    ],
                    conn: [
                      type: {:struct, Plug.Conn},
                      doc:
                        "*Phoenix only.* A prepared `Plug.Conn` for the first request: its test session " <>
                          "(`Plug.Test.init_test_session/2`), cookies, headers and assigns go with it, " <>
                          "as with `Phoenix.ConnTest`. To log in on both backends, add a cookie instead " <>
                          "([Logging in](usage.md#logging-in))."
                    ],
                    browser_context: [
                      type: :keyword_list,
                      doc:
                        "*Playwright only.* Options of `Playwright.Browser.new_context/2` for this session, " <>
                          "each over the test's (`Playwright.Test.use/1`), as for a context a test creates " <>
                          "itself. Not `base_url` or `extra_http_headers`: pass those to the session."
                    ],
                    browser: [
                      type: {:struct, Playwright.Browser},
                      doc:
                        "*Playwright only.* The `Playwright.Browser` the session's context is created in. " <>
                          "Defaults to the test's browser from `Playwright.Test.BrowserPool.browser/1`; " <>
                          "to override launch options such as `headless: false` for one test, " <>
                          "pass `Playwright.Test.BrowserPool.browser(launch_options: ...)` " <>
                          "([Playwright setup](installation.md#playwright-setup))."
                    ]
                  )

  # `config :fluffy`: only what Playwright has no concept of. Timeouts, the test id attribute
  # and the base URL are Playwright Test's (`config :playwright, :test`, `Playwright.Test.use/1`).
  @config_schema NimbleOptions.new!(
                   # A Phoenix session's timeout of operations without `timeout:`
                   # (`Fluffy.Timeouts`); `0` checks once.
                   phoenix_backend_timeout: [type: :timeout, default: 1_000],
                   endpoint: [type: :atom],
                   ecto_repos: [type: {:list, :atom}],
                   file_input_max_bytes: [type: :pos_integer, default: 10_000_000]
                 )

  @resolved_keys [:expect_timeout, :test_id_attribute, :phoenix_backend_timeout]

  @type session_option :: unquote(NimbleOptions.option_typespec(@session_schema))

  @doc false
  # A string or a regex; a `Regex` becomes its `Playwright.RegExp`, raising on PCRE-only syntax.
  def text_or_reg_exp(value) when is_binary(value) or is_struct(value, Playwright.RegExp), do: {:ok, value}
  def text_or_reg_exp(%Regex{} = value), do: {:ok, Playwright.RegExp.new(value)}
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

  @doc """
  Validates a cross-driver action's options for `session`. A Phoenix session raises
  `Fluffy.CapabilityError` for an option only Playwright honors, so its drivers get `timeout:`
  at most.
  """
  @spec validate_action!(Fluffy.Session.t(), atom(), keyword()) :: keyword()
  def validate_action!(%Fluffy.Session{} = session, action, options) do
    options = validate_action!(action, options)

    with Fluffy.Backend.Phoenix <- Fluffy.Session.backend(session),
         key when not is_nil(key) <- Enum.find(Keyword.keys(options), &(&1 in @playwright_option_keys)) do
      raise Fluffy.CapabilityError,
        capability: :playwright_action_options,
        operation: action,
        driver: Fluffy.Session.current_driver(session),
        detail: "#{inspect(key)} is a Playwright option"
    end

    options
  end

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

  @doc "`clear_cookies/2` filters as a map, a `Regex` as its `Playwright.RegExp`; a `nil` one filters nothing."
  @spec validate_clear_cookies!(keyword() | map()) :: map()
  def validate_clear_cookies!(options) do
    options
    |> Map.new()
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
    |> NimbleOptions.validate!(@clear_cookies_schema)
  end

  @spec validate_exact_locator!(keyword()) :: keyword()
  def validate_exact_locator!(options), do: NimbleOptions.validate!(options, @exact_locator_schema)

  @spec validate_role_locator!(keyword()) :: keyword()
  def validate_role_locator!(options), do: NimbleOptions.validate!(options, @role_locator_schema)

  @spec validate_filter_locator!(keyword()) :: keyword()
  def validate_filter_locator!(options), do: NimbleOptions.validate!(options, @filter_locator_schema)

  @spec validate_session!(atom(), keyword()) :: keyword()
  def validate_session!(backend, options) do
    options = NimbleOptions.validate!(options, @session_schema)

    for key <- [:browser, :browser_context], Keyword.has_key?(options, key) do
      Fluffy.CapabilityError.require_playwright!(
        backend,
        :browser_context_setters,
        :start_session,
        "#{inspect(key)} is an option of Playwright sessions"
      )
    end

    if backend == :playwright and Keyword.has_key?(options, :conn) do
      raise Fluffy.CapabilityError,
        capability: :phoenix_conn,
        operation: :start_session,
        backend: :playwright,
        detail: ":conn is an option of Phoenix sessions; add a cookie to log in on both backends"
    end

    if key = Enum.find([:base_url, :extra_http_headers], &Keyword.has_key?(options[:browser_context] || [], &1)) do
      # One place each: the session's own options, the same on both backends.
      raise ArgumentError, "pass `#{key}:` to start_session/2, not in `browser_context:`"
    else
      :ok
    end

    validate_conn!(options[:conn])

    options
  end

  @doc false
  # The setting `key`: `phoenix_backend_timeout` Fluffy's, the others Playwright's
  # (`Playwright.Test.config/0`, its defaults filled in), where `0` means no limit:
  # `:infinity` here.
  @spec config!(atom()) :: term()
  def config!(:test_id_attribute) do
    # Validated as it is read, so a bad attribute fails only `by_test_id`.
    case Map.fetch!(resolved_config!(), :test_id_attribute) do
      {:ok, names} -> names
      {:error, message} -> raise ArgumentError, "invalid config :playwright, :test: test_id_attribute: " <> message
    end
  end

  def config!(key) when key in @resolved_keys, do: Map.fetch!(resolved_config!(), key)

  # Read on every timeout, so resolved once per env, as Playwright's
  # `Matchers.Expect.app_env_expect_config/0`: keyed on the values it resolves from, and
  # validated in full (`config!/0`) on a miss, so an invalid value raises on each read.
  defp resolved_config! do
    env =
      {Application.get_env(:fluffy, :phoenix_backend_timeout), Application.get_env(:playwright, :test),
       Application.get_env(:playwright, :expect)}

    case :persistent_term.get({__MODULE__, :config}, nil) do
      {^env, config} ->
        config

      _stale ->
        config = resolve_config!()
        :persistent_term.put({__MODULE__, :config}, {env, config})
        config
    end
  end

  defp resolve_config! do
    fluffy = config!()
    playwright = Playwright.Test.config()

    %{
      expect_timeout: Fluffy.Timeouts.no_limit(playwright.expect.timeout),
      test_id_attribute: test_id_attribute(playwright.test_id_attribute),
      phoenix_backend_timeout: Keyword.fetch!(fluffy, :phoenix_backend_timeout)
    }
  end

  @doc false
  # `config :fluffy`, validated: a misspelt key raises, as kept it would silently do
  # nothing. A module's config (`config :fluffy, Fluffy.Sandbox, ...`) is validated by the
  # module, which has to exist.
  @spec config!() :: keyword()
  def config! do
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

  @doc false
  # As Playwright.Test's `test_id_attribute`: one attribute or a comma-separated list.
  # Upstream's test id engine puts each name into a CSS attribute selector unescaped, so
  # it must be a CSS identifier; other names make each `by_test_id` fail in the browser.
  def test_id_attribute(names) when is_binary(names) and names != "" do
    case Enum.reject(String.split(names, ","), &css_identifier?/1) do
      [] ->
        {:ok, names}

      invalid ->
        {:error,
         "expected attribute names that are CSS identifiers, separated by commas without spaces, " <>
           "got: #{inspect(names)} (invalid: #{Enum.map_join(invalid, ", ", &inspect/1)})"}
    end
  end

  def test_id_attribute(names), do: {:error, "expected a non-empty string, got: #{inspect(names)}"}

  # CSS Syntax's ident-token without escapes; name characters include any non-ASCII one.
  defp css_identifier?(name),
    do: Regex.match?(~r/\A(?:--|-?[A-Za-z_\x{80}-\x{10FFFF}])[A-Za-z0-9_\x{80}-\x{10FFFF}-]*\z/u, name)

  defp validate_conn!(nil), do: :ok

  defp validate_conn!(%Plug.Conn{state: :unset}), do: :ok

  defp validate_conn!(%Plug.Conn{state: state}) do
    raise ArgumentError,
          ":conn must be a fresh, unsent %Plug.Conn{} with state :unset, got: #{inspect(state)}"
  end
end
