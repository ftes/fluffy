%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [".credo.exs", "mix.exs", "config/", "lib/", "test/"],
        excluded: []
      },
      strict: true,
      checks: %{
        enabled: [
          # Typed action/expectation dispatchers have many flat variants; keep
          # them flat and cap the resulting branch count instead of splitting
          # one protocol operation across arbitrary modules.
          {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 16]},
          # A case inside an iterator is common in state reconciliation. A
          # fourth nesting level still requires extraction.
          {Credo.Check.Refactor.Nesting, [max_nesting: 3]}
        ],
        disabled: [
          # Styler owns deterministic alias lifting and its conflict handling.
          {Credo.Check.Design.AliasUsage, []},
          # The standard formatter is the source of truth for line wrapping.
          {Credo.Check.Readability.MaxLineLength, []}
        ]
      }
    }
  ]
}
