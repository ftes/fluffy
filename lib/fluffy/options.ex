defmodule Fluffy.Options do
  @moduledoc false

  @timeout_options [
    timeout: [
      type: :non_neg_integer,
      doc:
        "Maximum time in milliseconds to wait for the operation. " <>
          "Playwright browser bookkeeping and navigation synchronization use the session timeout separately."
    ]
  ]

  @action_schema NimbleOptions.new!(@timeout_options)
  @expectation_schema NimbleOptions.new!(@timeout_options)
  @checked_expectation_schema NimbleOptions.new!(
                                @timeout_options ++
                                  [
                                    checked: [
                                      type: :boolean,
                                      doc: "Set to false to expect an unchecked control."
                                    ],
                                    indeterminate: [
                                      type: :boolean,
                                      doc: "Expect the browser-owned indeterminate state."
                                    ]
                                  ]
                              )

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
                         name: [
                           type: :string,
                           doc: "Restrict the role locator by accessible name."
                         ],
                         exact: [
                           type: :boolean,
                           doc: "Require an exact, case-sensitive accessible-name match."
                         ]
                       )

  @test_id_locator_schema NimbleOptions.new!(
                            attribute: [
                              type: :string,
                              default: "data-testid",
                              doc: "Attribute used as the test-id source."
                            ]
                          )

  @filter_locator_schema NimbleOptions.new!(
                           has: [
                             type: {:struct, Fluffy.Locator},
                             type_spec: quote(do: Fluffy.Locator.t()),
                             doc: "Keep elements containing a match for this locator."
                           ],
                           has_text: [
                             type: :string,
                             doc: "Keep elements containing this normalized text."
                           ],
                           has_not: [
                             type: {:struct, Fluffy.Locator},
                             type_spec: quote(do: Fluffy.Locator.t()),
                             doc: "Keep elements containing no match for this locator."
                           ],
                           has_not_text: [
                             type: :string,
                             doc: "Keep elements that do not contain this normalized text."
                           ]
                         )

  @download_event_schema NimbleOptions.new!(
                           @timeout_options ++
                             [
                               max_bytes: [
                                 type: :non_neg_integer,
                                 doc: "Maximum number of response bytes to retain; defaults to 10,000,000."
                               ]
                             ]
                         )

  @dialog_event_schema NimbleOptions.new!(
                         @timeout_options ++
                           [
                             decision: [
                               type:
                                 {:or,
                                  [
                                    {:in, [:accept, :dismiss]},
                                    {:tuple, [{:in, [:accept]}, :string]},
                                    {:fun, 1}
                                  ]},
                               type_spec:
                                 quote(
                                   do:
                                     :accept
                                     | :dismiss
                                     | {:accept, String.t()}
                                     | (Fluffy.Dialog.t() ->
                                          :accept | :dismiss | {:accept, String.t()})
                                 ),
                               type_doc: "`:accept`, `:dismiss`, `{:accept, prompt_text}`, or a one-argument function",
                               doc: "Accept, dismiss, accept with prompt text, or decide from the captured dialog."
                             ],
                             accept: [
                               type: {:or, [{:in, [true]}, :string]},
                               type_spec: quote(do: true | String.t()),
                               type_doc: "`true` or `t:String.t/0`",
                               doc: "Compatibility shorthand for accepting, optionally with prompt text."
                             ],
                             dismiss: [
                               type: {:in, [true]},
                               type_spec: quote(do: true),
                               type_doc: "`true`",
                               doc: "Compatibility shorthand for dismissing the dialog."
                             ]
                           ]
                       )

  @normalized_dialog_event_schema NimbleOptions.new!(
                                    @timeout_options ++
                                      [
                                        decision: [
                                          type:
                                            {:or,
                                             [
                                               {:in, [:accept, :dismiss]},
                                               {:tuple, [{:in, [:accept]}, :string]},
                                               {:fun, 1}
                                             ]},
                                          type_spec:
                                            quote(
                                              do:
                                                :accept
                                                | :dismiss
                                                | {:accept, String.t()}
                                                | (Fluffy.Dialog.t() ->
                                                     :accept | :dismiss | {:accept, String.t()})
                                            )
                                        ]
                                      ]
                                  )

  @network_matcher_type {:or, [:string, {:struct, Regex}, {:fun, 1}]}

  @network_event_schema NimbleOptions.new!(
                          @timeout_options ++
                            [
                              matcher: [
                                type: @network_matcher_type,
                                type_spec: quote(do: String.t() | Regex.t() | (term() -> boolean())),
                                doc: "URL string, regular expression, or one-argument event predicate."
                              ]
                            ]
                        )

  @evaluate_schema NimbleOptions.new!(
                     arg: [
                       type: :any,
                       default: nil,
                       doc: "Serializable argument passed to a function-style expression."
                     ],
                     is_function: [
                       type: :boolean,
                       default: false,
                       doc: "Treat the expression as a JavaScript function."
                     ],
                     timeout: [
                       type: {:or, [nil, :non_neg_integer]},
                       default: nil,
                       type_doc: "`t:non_neg_integer/0` or `nil`",
                       doc: "Maximum evaluation time in milliseconds; defaults to the session timeout."
                     ]
                   )

  @viewport_schema [
    width: [type: :pos_integer, required: true],
    height: [type: :pos_integer, required: true]
  ]

  @browser_context_schema [
    accept_downloads: [type: :boolean],
    bypass_csp: [type: :boolean],
    color_scheme: [type: {:in, [:light, :dark, :no_preference, nil]}],
    contrast: [type: {:in, [:no_preference, :more, nil]}],
    device_scale_factor: [type: {:or, [:integer, :float]}],
    extra_http_headers: [type: {:map, :string, :string}],
    forced_colors: [type: {:in, [:active, :none, nil]}],
    geolocation: [type: :map],
    has_touch: [type: :boolean],
    http_credentials: [type: :map],
    ignore_https_errors: [type: :boolean],
    is_mobile: [type: :boolean],
    java_script_enabled: [type: :boolean],
    locale: [type: :string],
    offline: [type: :boolean],
    permissions: [type: {:list, :string}],
    proxy: [type: :map],
    reduced_motion: [type: {:in, [:reduce, :no_preference, nil]}],
    screen: [type: :map, keys: @viewport_schema],
    service_workers: [type: {:in, [:allow, :block]}],
    storage_state: [type: {:or, [:string, :map]}],
    strict_selectors: [type: :boolean],
    timezone_id: [type: :string],
    user_agent: [type: :string],
    viewport: [type: {:or, [nil, map: @viewport_schema]}]
  ]

  @setup_schema NimbleOptions.new!(
                  repos: [type: {:list, :atom}],
                  sandbox: [type: :boolean],
                  timeout: [type: :pos_integer]
                )

  @session_schema NimbleOptions.new!(
                    endpoint: [type: :atom],
                    base_url: [type: :string],
                    headers: [type: {:list, {:tuple, [{:or, [:atom, :string]}, :string]}}],
                    conn: [type: {:struct, Plug.Conn}],
                    timeout: [type: :pos_integer],
                    browser_context: [type: :keyword_list, keys: @browser_context_schema]
                  )

  @launch_schema [
    args: [type: {:list, :string}],
    channel: [type: :string],
    executable_path: [type: :string],
    headless: [type: :boolean],
    slow_mo: [type: {:or, [:integer, :float]}]
  ]

  @playwright_schema NimbleOptions.new!(
                       enabled: [type: :boolean, default: true],
                       engine: [type: {:in, [:chromium, :firefox, :webkit]}, default: :chromium],
                       executable: [type: :string],
                       timeout: [type: :pos_integer, default: 15_000],
                       launch_options: [type: :keyword_list, keys: @launch_schema, default: []],
                       artifact_dir: [type: {:or, [nil, :string]}],
                       trace_dir: [type: :string, default: "traces"],
                       js_logger: [type: :atom, default: Fluffy.Playwright.ConsoleLogger]
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
  def expectation_schema, do: @expectation_schema

  @doc false
  def checked_expectation_schema, do: @checked_expectation_schema

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

  @doc false
  def download_event_schema, do: @download_event_schema

  @doc false
  def dialog_event_schema, do: @dialog_event_schema

  @doc false
  def network_event_schema, do: @network_event_schema

  @doc false
  def evaluate_schema, do: @evaluate_schema

  @spec validate_action!(keyword()) :: keyword()
  def validate_action!(options), do: NimbleOptions.validate!(options, @action_schema)

  @spec validate_expectation!(keyword()) :: keyword()
  def validate_expectation!(options), do: NimbleOptions.validate!(options, @expectation_schema)

  @spec validate_checked_expectation!(keyword()) :: keyword()
  def validate_checked_expectation!(options), do: NimbleOptions.validate!(options, @checked_expectation_schema)

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

  @spec validate_event_constructor!(atom(), keyword()) :: keyword()
  def validate_event_constructor!(:dialog, options), do: NimbleOptions.validate!(options, @dialog_event_schema)
  def validate_event_constructor!(:download, options), do: NimbleOptions.validate!(options, @download_event_schema)

  def validate_event_constructor!(type, options) when type in [:file_chooser, :navigation, :page, :request, :response] do
    NimbleOptions.validate!(options, @action_schema)
  end

  @spec validate_event!(atom(), keyword()) :: keyword()
  def validate_event!(:dialog, options), do: NimbleOptions.validate!(options, @normalized_dialog_event_schema)
  def validate_event!(:download, options), do: NimbleOptions.validate!(options, @download_event_schema)

  def validate_event!(type, options) when type in [:file_chooser, :navigation, :page] do
    NimbleOptions.validate!(options, @action_schema)
  end

  def validate_event!(type, options) when type in [:request, :response] do
    NimbleOptions.validate!(options, @network_event_schema)
  end

  def validate_event!(_backend_event, options), do: options

  @spec validate_evaluate!(keyword()) :: keyword()
  def validate_evaluate!(options), do: NimbleOptions.validate!(options, @evaluate_schema)

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

  @spec validate_playwright!(false | keyword()) :: false | keyword()
  def validate_playwright!(false), do: false

  def validate_playwright!(options) when is_list(options) do
    options = NimbleOptions.validate!(options, @playwright_schema)

    if options[:enabled] and is_nil(options[:executable]) do
      raise ArgumentError, "enabled Fluffy Playwright configuration requires :executable"
    end

    validate_js_logger!(options[:js_logger])

    options
  end

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

  defp validate_js_logger!(false), do: :ok

  defp validate_js_logger!(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :log, 3) do
      :ok
    else
      raise ArgumentError,
            ":js_logger must be false or a module implementing log/3, got: #{inspect(module)}"
    end
  end
end
