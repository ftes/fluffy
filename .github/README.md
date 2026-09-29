# Dependency updates

Install the [Renovate GitHub App](https://github.com/apps/renovate) for this
repository to activate `renovate.json`. The hosted app creates update PRs during
the Monday 00:00–06:59 Europe/Berlin window, with a two-day release age where
release timestamps are available. Updates require review; automerge is disabled.

Renovate discovers both the root and `integration/consumer` Mix projects, npm
packages, GitHub Actions and `.tool-versions`. Action references remain pinned to
full commit SHAs. Toolchain updates are grouped, including pnpm's pin in
`package.json`, and patch, minor and major upgrades are all eligible for PRs.
The minimum supported Node version remains a manual compatibility decision.
Elixir keeps its OTP compatibility suffix; an Erlang major upgrade may require
adjusting that suffix to a compatible Elixir build before the PR can pass CI.

CI's newest lane reads `.tool-versions`. The oldest lane copies
`.tool-versions.oldest` over it and aligns `package.json` with that lane's pnpm
version. Renovate ignores the oldest toolchain file.

Keep GitHub's Dependabot security alerts enabled independently of Renovate.
The former Dependabot version-update configuration and custom toolchain workflow
have been removed. Renovate App PRs trigger normal pull-request CI.

Dependency ranges use Renovate's `replace` strategy: out-of-range updates replace
the existing range instead of widening support to include both release lines.
