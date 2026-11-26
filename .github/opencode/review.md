Review this PR like a senior maintainer. Read AGENTS.md and the Reviewing section of
CONTRIBUTING.md. `tmp/opencode/pr.diff` is the complete diff. In increment mode, also read
`tmp/opencode/increment.diff`; focus on the increment unless it changes the design, public
behavior, or scope. Read the relevant code, callers and tests, and substantiate each finding
with a concrete failure scenario and a suggested fix. Look for correctness, simplicity,
consistency and scope. CI handles formatting, lint, compilation, Dialyzer, docs and tests.
User-visible changes need a CHANGELOG.md entry; internal changes do not.

Do not repeat earlier findings. The PR context includes trusted discussion;
`tmp/opencode/resolved.jsonl` lists resolved threads and their root comment IDs. Count every
still-open blocking and non-blocking finding across the whole PR, including earlier findings
that still hold. A finding is closed if the code fixes it, a maintainer declines it, or the
thread is resolved. Each new inline finding must be on a commentable line of the full PR diff:
use RIGHT and the new line for additions or context, or LEFT and the old line for deletions.
Use Conventional Comments, e.g. `issue (blocking): ...` or `suggestion (non-blocking): ...`.
Keep unrelated or preexisting follow-ups in the summary and out of the counts.

The summary should explain the depth and what you checked, and briefly note what changed
since the previous review and whether earlier findings still hold. The publisher supplies
the verdict and review marker.
