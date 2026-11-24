defmodule Fluffy.MixProject do
  use Mix.Project

  @version "0.9.0-rc.5"
  @description "Phoenix feature tests. Three drivers, one Playwright-shaped API."
  @source_url "https://github.com/ftes/fluffy"
  @hex_url "https://hex.pm/packages/fluffy"

  @guides [
    "docs/why-fluffy.md",
    "docs/installation.md",
    "docs/usage.md",
    "docs/locators.md",
    "docs/actions.md",
    "docs/assertions.md",
    "docs/debugging.md",
    "docs/advanced-events.md"
  ]

  @migration [
    "docs/migration-from-phoenix-test.md",
    "docs/upgrading.md"
  ]

  @reference [
    "docs/capabilities.md",
    "CHANGELOG.md",
    "LICENSE.md"
  ]

  @doc_files Enum.uniq(@guides ++ @migration ++ @reference)

  def project do
    [
      app: :fluffy,
      version: @version,
      name: "Fluffy",
      description: @description,
      source_url: @source_url,
      homepage_url: @hex_url,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: docs(),
      package: package(),
      deps: deps(),
      aliases: aliases(),
      usage_rules: usage_rules(),
      dialyzer: [plt_add_apps: [:ex_unit, :mix]]
    ]
  end

  def application do
    [
      extra_applications: [:inets, :logger],
      mod: {Fluffy.Application, []}
    ]
  end

  def cli do
    [preferred_envs: [lint: :test, check: :test]]
  end

  # `dev/` holds maintainer tasks, kept out of the package and consumers' builds.
  defp elixirc_paths(:test), do: ["lib", "dev", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      # The runtime floors are what CI's oldest lane runs: mix.lock.oldest locks each one.
      {:nimble_options, "~> 1.1"},
      {:lazy_html, ">= 0.1.13 and < 1.0.0"},
      {:phoenix, "~> 1.7 and >= 1.7.10"},
      {:phoenix_live_view, "~> 1.1 and >= 1.1.32"},
      {:playwright, "~> 1.65.0-rc.4", hex: :playwright_ex},
      {:phoenix_ecto, "~> 4.6 and >= 4.6.6", optional: true},
      {:ecto_sql, "~> 3.10", optional: true},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false},
      {:usage_rules, "~> 1.3", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.12", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:esbuild, "~> 0.10.1", only: [:dev, :test], runtime: false},
      {:bandit, "~> 1.0", only: :test},
      {:postgrex, ">= 0.16.0 and < 1.0.0", only: :test}
    ]
  end

  defp docs do
    [
      main: "readme",
      # Maintainer tasks in `dev/` are not part of the package.
      filter_modules: fn module, _metadata ->
        module != Mix.Tasks.Fluffy.PlaywrightSource
      end,
      annotations_for_docs: fn metadata ->
        if metadata[:playwright_only], do: ["Playwright only"], else: []
      end,
      source_ref: "v#{@version}",
      # The `:playwright` app's Hex package is `playwright_ex`; ex_doc would link the app name,
      # the other library `playwright` on Hex.
      deps: [playwright: "https://hexdocs.pm/playwright_ex"],
      # They name functions that later releases removed.
      skip_undefined_reference_warnings_on: ["CHANGELOG.md", "docs/upgrading.md"],
      extras: ["README.md"] ++ @doc_files,
      groups_for_extras: [
        Guides: @guides,
        Migration: @migration,
        Reference: @reference
      ],
      groups_for_modules: [
        "Core API": [
          Fluffy,
          Fluffy.Locator,
          Fluffy.FrameLocator,
          Fluffy.Expect,
          Fluffy.Assert,
          Fluffy.PhoenixTest,
          Fluffy.Page,
          Fluffy.Event,
          Fluffy.Event.Pending,
          Fluffy.Sandbox
        ],
        Playwright: [
          Fluffy.Playwright,
          Fluffy.Playwright.Clock,
          Fluffy.Playwright.Keyboard,
          Fluffy.Playwright.Mouse
        ],
        "Sessions and results": [
          Fluffy.Session,
          Fluffy.PhoenixTest.Session,
          Fluffy.Download,
          Fluffy.FileChooser,
          Fluffy.FilePayload
        ],
        "Capabilities and errors": [
          Fluffy.Capability,
          Fluffy.CapabilityError,
          Fluffy.ActionabilityError,
          Fluffy.StrictnessError,
          Fluffy.OperationError,
          Fluffy.LiveViewError
        ]
      ]
    ]
  end

  defp package do
    [
      name: "fluffy",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "Hex.pm" => @hex_url},
      files: ["lib", ".formatter.exs", "mix.exs", "README.md", "usage-rules.md" | @doc_files]
    ]
  end

  # `mix usage_rules.sync --yes` writes these skills to `.agents/skills` (`.claude/skills` links
  # there).
  defp usage_rules do
    [
      skills: [
        location: ".agents/skills",
        build: [
          "usage-rules": [
            description:
              "Use when looking up docs for Elixir, OTP or a dependency: `mix usage_rules.docs` and `mix usage_rules.search_docs`.",
            usage_rules: [{:usage_rules, sub_rules: []}]
          ],
          phoenix: [
            description:
              "Use when writing the Phoenix fixtures under test/ (HEEx templates, LiveViews, components). The rules are written for applications.",
            usage_rules: ["phoenix:html", "phoenix:liveview"]
          ],
          playwright: [
            description:
              "Use when calling Playwright from Fluffy's Playwright driver, or checking the Playwright API Fluffy wraps.",
            usage_rules: [:playwright]
          ]
        ]
      ]
    ]
  end

  defp aliases do
    [
      setup: [
        "deps.get",
        "assets.build",
        "playwright.install chromium",
        "fluffy.playwright_source"
      ],
      "consumer.regenerate": "run --no-start integration/regenerate_consumer.exs",
      "assets.build": ["esbuild.install --if-missing", "esbuild test_browser"],
      # What CI's checks job runs. Compiles strictly before a later task's own compile could
      # satisfy it. Dialyzer is last, so CI can append `--format github`.
      lint: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "usage_rules.sync --check",
        "credo --format oneline",
        "cmd env MIX_ENV=dev mix docs --warnings-as-errors",
        "dialyzer --format short --list-unused-filters"
      ],
      check: ["lint", "test --warnings-as-errors"]
    ]
  end
end
