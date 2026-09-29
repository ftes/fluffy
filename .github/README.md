# Dependency updates

Install the [Renovate GitHub App](https://github.com/apps/renovate) for this
repository to activate `renovate.json`. The hosted app creates update PRs during
the Monday 00:00–06:59 Europe/Berlin window, with a two-day release age where
release timestamps are available (three days for npm via the best-practices preset). Updates require review; automerge is disabled.

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

Renovate extends `config:best-practices`, including action/container digest pins,
development-dependency pins and weekly lockfile maintenance. Mix overrides the
preset's development-dependency pinning with `widen`: weekly maintenance lets Mix
resolve the newest allowed versions in `mix.lock`, while out-of-range releases
produce PRs widening `mix.exs` constraints without dropping existing support.
These compatibility changes require review; automerge remains disabled.
Two-part `~> 0.x` constraints use equivalent explicit ranges such as
`>= 0.3.0 and < 1.0.0` to avoid Renovate incorrectly treating later `0.x` releases
as out of range. Three-part constraints such as `~> 0.3.0` retain their syntax.
Other dependency ranges retain `replace`, except where the preset pins
development dependencies.

Renovate generates Mix lockfiles with OTP 29 and Elixir 1.20.4, configured via
`constraints`. Its Mix worker otherwise defaults to OTP 26, which cannot run
Elixir 1.20. These worker constraints do not restrict proposed toolchain updates;
review them when adopting a newer Elixir/OTP release line.
