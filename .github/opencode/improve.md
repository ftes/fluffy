Find one valuable simplification or consistency improvement in or touching tonight's focus.
Read AGENTS.md, the relevant code, its callers and tests. Look for duplicate logic, dead code,
needless indirection or options, or a concept handled differently across drivers. Prefer
the smallest change that removes the most complexity. Skip ideas overlapping open nightly PRs
or repeating closed ones; `why` holds reasons that were recorded.

Keep observable behavior and driver boundaries. No features, bug fixes, dependency or CI
changes, cosmetic churn or CHANGELOG entry. Run `mix format`, `mix compile --warnings-as-errors`
and `mix credo --format oneline`. CI runs the tests. Return `publish` with an imperative title
and a short PR body explaining what this simplifies, or `none` with the reason in the body if
nothing is clearly worth doing.
