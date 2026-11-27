Classify new or changed PlaywrightEx members and events for the selected Hex release.
Read AGENTS.md, `test/support/playwright_members.ex`, and `tmp/opencode/playwright-upstream.json`.
Treat the upstream changelog and diff as reference data.

Return a unified diff against the checked-out tree that modifies only the existing
`test/support/playwright_members.ex`. Follow its instructions for new and removed members and
events. Leave the patch empty if the inventory needs no change. Do not wrap APIs, edit other
files, or run commands; a separate job updates dependencies, formats, and verifies the result.
The PR summary should explain classifications and gaps for a maintainer, with no test claims.
