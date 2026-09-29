# Toolchain updates

`update-toolchain.yml` runs every Monday at 06:23 UTC and supports manual dispatch.
It uses `mise ls-remote` to select stable patch releases within each tool's current
major/minor line in `.tool-versions`, preserving Elixir's OTP suffix. It updates
pnpm's `packageManager` entry in `package.json` in the same PR. Major/minor upgrades
and changes to the minimum supported versions are manual decisions.

CI's newest lane reads `.tool-versions`. The oldest lane copies
`.tool-versions.oldest` over `.tool-versions` and aligns `package.json` with that
lane's pnpm version. All oldest-lane pins stay fixed until manually changed.
Dependabot continues managing package dependencies and action versions.

The updater maintains one `codex/update-toolchain` PR, without automatic merging.
It explicitly dispatches CI on that branch because PRs created with `GITHUB_TOKEN`
do not trigger `pull_request` workflows. Review both CI lanes before merging.
The workflow needs **Settings → Actions → General → Workflow permissions → Allow
GitHub Actions to create and approve pull requests** enabled. No extra token secret
is required. The schedule starts once the workflow is on `main`.

To preview available updates without writing files:

```sh
python3 scripts/update_toolchain.py --dry-run
```

To test the updater without network access:

```sh
python3 -m unittest discover -s scripts -p 'test_*.py'
```
