Read the PR details and diff in `tmp/opencode/<PR>.json` and `.diff`. Read
`tmp/review-threads/<PR>.md` if present and `tmp/ci-failed.log` if CI failed. Verify each
finding against the code and fix the ones that hold. Keep the simplification and the public
behavior. Don't merge or rebase on main, or weaken or skip tests. Postgres and Chromium are
available; reproduce and check failures with `mix test test/<file>.exs`. Also run `mix format`,
`mix compile --warnings-as-errors` and `mix credo --format oneline` for changes.

Use `fix` after making changes that fix the PR, `retry` for an unrelated CI failure such as a
flake (you may also fix review findings), `close` if a CI failure requires redesigning the PR,
or `none` when CI is passing and no changes are needed. The message is an imperative commit
subject for changes or a one-sentence reason for closing. Answer every listed thread by its
ID, unless closing. Use `fixed: true` only when an existing or proposed change fixes it;
otherwise explain why it doesn't hold.
