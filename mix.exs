defmodule Fluffy.MixProject do
  use Mix.Project

  @version "0.2.0"
  @description "Phoenix feature testing — 3 drivers, 1 API: Static, LiveView, Playwright."
  @source_url "https://github.com/ftes/fluffy"
  @hex_url "https://hex.pm/packages/fluffy"

  @guides [
    "docs/installation.md",
    "docs/usage.md",
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
      dialyzer: [plt_add_apps: [:ex_unit]]
    ]
  end

  def application do
    [
      extra_applications: [:inets, :logger],
      mod: {Fluffy.Application, []}
    ]
  end

  def cli do
    [preferred_envs: [check: :test, quality: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:nimble_options, "~> 1.1"},
      {:lazy_html, "~> 0.1"},
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:playwright_ex, "~> 0.9"},
      {:phoenix_ecto, "~> 4.7", optional: true},
      {:ecto_sql, "~> 3.10", optional: true},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false},
      {:styler, "~> 1.12", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:bandit, "~> 1.0", only: :test},
      {:postgrex, "~> 0.22", only: :test}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      assets: %{"docs/images" => "docs/images"},
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
          Fluffy.Expect,
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
          Fluffy.HTTPEvent,
          Fluffy.NavigationEvent,
          Fluffy.Playwright.Handle
        ],
        "Capabilities and errors": [
          Fluffy.Capability,
          Fluffy.CapabilityError,
          Fluffy.ActionabilityError,
          Fluffy.StrictnessError,
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
      files: ["lib", "docs/images", ".formatter.exs", "mix.exs", "README.md" | @doc_files]
    ]
  end

  defp aliases do
    [
      setup: [
        "deps.get",
        "cmd pnpm install --frozen-lockfile",
        "assets.build",
        "cmd pnpm exec playwright install chromium"
      ],
      "consumer.regenerate": "run --no-start integration/regenerate_consumer.exs",
      "assets.build": ["cmd pnpm run build:test"],
      check: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --format oneline",
        "test --warnings-as-errors"
      ],
      quality: ["check", "dialyzer --format short --list-unused-filters"]
    ]
  end
end
