defmodule Fluffy.MixProject do
  use Mix.Project

  @version "0.8.0"
  @description "Phoenix feature tests. Three drivers, one Playwright-shaped API."
  @source_url "https://github.com/ftes/fluffy"
  @hex_url "https://hex.pm/packages/fluffy"

  @guides [
    "docs/installation.md",
    "docs/usage.md",
    "docs/assertion-styles.md",
    "docs/advanced-events.md"
  ]

  @migration [
    "docs/migration-from-phoenix-test.md"
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
      {:playwright_ex, "~> 0.17.0-rc.1"},
      {:phoenix_ecto, "~> 4.7", optional: true},
      {:ecto_sql, "~> 3.10", optional: true},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false},
      {:styler, "~> 1.12", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:bandit, "~> 1.0", only: :test},
      {:postgrex, ">= 0.22.0 and < 1.0.0", only: :test}
    ]
  end

  defp docs do
    [
      main: "readme",
      # Maintainer tasks in `dev/` are not part of the package.
      filter_modules: fn module, _metadata -> module != Mix.Tasks.Fluffy.Gen.NativeOptions end,
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
          Fluffy.Playwright,
          Fluffy.Sandbox
        ],
        "Sessions and results": [
          Fluffy.Session,
          Fluffy.Download,
          Fluffy.Dialog,
          Fluffy.FileChooser,
          Fluffy.FilePayload,
          Fluffy.Request,
          Fluffy.Response,
          Fluffy.Frame,
          Fluffy.Event.Pending
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
      files: ["lib", ".formatter.exs", "mix.exs", "README.md" | @doc_files]
    ]
  end

  defp aliases do
    [
      setup: [
        "deps.get",
        "cmd pnpm install --frozen-lockfile",
        "assets.build",
        "playwright_ex.install -- chromium"
      ],
      "consumer.regenerate": "run --no-start integration/regenerate_consumer.exs",
      "assets.build": ["cmd pnpm run build:test"],
      lint: [
        "format --check-formatted",
        # Compiles strictly first: the generator's own compile would satisfy it.
        "compile --warnings-as-errors",
        "fluffy.gen.native_options --check",
        "credo --format oneline"
      ],
      check: ["lint", "test --warnings-as-errors"],
      quality: ["check", "dialyzer --format short --list-unused-filters"]
    ]
  end
end
