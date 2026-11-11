defmodule Fluffy.MixProject do
  use Mix.Project

  @version "0.9.0-rc.2"
  @description "Phoenix feature tests. Three drivers, one Playwright-shaped API."
  @source_url "https://github.com/ftes/fluffy"
  @hex_url "https://hex.pm/packages/fluffy"

  @guides [
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
    [preferred_envs: [lint: :test, check: :test, quality: :test]]
  end

  # `dev/` holds maintainer tasks, kept out of the package and consumers' builds.
  defp elixirc_paths(:test), do: ["lib", "dev", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:nimble_options, "~> 1.1"},
      {:lazy_html, ">= 0.1.0 and < 1.0.0"},
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      # Until a release includes ftes/playwright_ex#191.
      {:playwright_ex, github: "ftes/playwright_ex", branch: "main"},
      {:phoenix_ecto, "~> 4.7", optional: true},
      {:ecto_sql, "~> 3.10", optional: true},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false},
      {:usage_rules, "~> 1.3", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.12", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:esbuild, "~> 0.10.1", only: [:dev, :test], runtime: false},
      {:bandit, "~> 1.0", only: :test},
      {:postgrex, ">= 0.22.0 and < 1.0.0", only: :test}
    ]
  end

  defp docs do
    [
      main: "readme",
      # Maintainer tasks in `dev/` are not part of the package.
      filter_modules: fn module, _metadata ->
        module not in [Mix.Tasks.Fluffy.Gen.NativeOptions, Mix.Tasks.Fluffy.PlaywrightSource]
      end,
      annotations_for_docs: fn metadata ->
        if metadata[:playwright_only], do: ["Playwright only"], else: []
      end,
      source_ref: "v#{@version}",
      extras: ["README.md"] ++ @doc_files,
      groups_for_extras: [
        Guides: @guides,
        Migration: @migration,
        Reference: @reference
      ],
      groups_for_modules: [
        "Core API": [
          Fluffy,
          Fluffy.Test,
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
          Fluffy.Dialog,
          Fluffy.FileChooser,
          Fluffy.FilePayload,
          Fluffy.Request,
          Fluffy.Response,
          Fluffy.Route,
          Fluffy.Frame,
          Fluffy.ConsoleMessage,
          Fluffy.PageError,
          Fluffy.Worker,
          Fluffy.WebSocket
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

  # `mix usage_rules.sync --yes` rewrites the managed block of AGENTS.md from this list.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        {:usage_rules, sub_rules: []},
        "phoenix:html",
        {"phoenix:liveview", link: :markdown},
        {:playwright_ex, link: :markdown}
      ]
    ]
  end

  defp aliases do
    [
      setup: [
        "deps.get",
        "assets.build",
        "playwright_ex.install -- chromium",
        "fluffy.playwright_source"
      ],
      "consumer.regenerate": "run --no-start integration/regenerate_consumer.exs",
      "assets.build": ["esbuild.install --if-missing", "esbuild test_browser"],
      lint: [
        "format --check-formatted",
        # Compiles strictly first: the generator's own compile would satisfy it.
        "compile --warnings-as-errors",
        "fluffy.gen.native_options --check",
        "usage_rules.sync --check",
        "credo --format oneline"
      ],
      check: ["lint", "test --warnings-as-errors"],
      quality: ["check", "dialyzer --format short --list-unused-filters"]
    ]
  end
end
