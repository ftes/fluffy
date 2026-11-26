# OpenCode workflows

The jobs use OpenCode V2 `2.4.2` and `opencode-go/kimi-k3.1-pro`. Set the
repository Actions variable `OPENCODE_CLIENT_ID` to the public OpenCode OAuth
client ID for `ftes/fluffy`. The same client ID has been verified on both
pull-request and branch-push runs.

Install the [OpenCode GitHub App](https://github.com/apps/opencode-agent) on the
repository. CI exchanges GitHub OIDC for model access and, only for publishing,
for an App installation token. The App can submit reviews and its pushes and
PRs trigger CI. Neither exchange requires a static secret.

`run.py` supplies scoped repository context, runs a private archived session
with sharing disabled, validates the final JSON, and publishes the result.
Only the publisher uses GitHub credentials. The model may run selected local
Mix commands in edit jobs, so those jobs still require trusted repository code.

Maintainers can use `@opencode`, `/opencode` or `/oc`; legacy `@claude` requests,
review history and automation branches are still recognized.

Local workflow checks:

```sh
actionlint
python3 -B -m unittest discover -s .github/opencode
```
