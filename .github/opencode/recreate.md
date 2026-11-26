Redo the old simplification PR on current main, preserving changes made since. Read
`tmp/opencode/<PR>.json` and `.diff` for the old change. Keep the old title if it still
fits and update the description if the change differs. Run `mix format`,
`mix compile --warnings-as-errors` and `mix credo --format oneline`; CI runs the suite.
Return action `publish` with a title and PR body, or `close` with a one-line reason as
the title if the change cannot be redone without redesigning it.
