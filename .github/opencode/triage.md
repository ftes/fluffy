An earlier nightly run opened each listed simplification PR. Current main is checked out.
For each PR, read `tmp/opencode/<PR>.json`, its `.diff` and the current code and callers
it touches. Keep by default; omit kept PRs from `decisions`. Close if main made it obsolete
or wrong. Redo only if its idea still holds but changes to the code or callers made its
implementation wrong on current main. A branch named `{claude,opencode}/nightly-<run>-<old PR>`
is already a redo; keep or close it. Merge conflicts, age and a preference for other work
aren't reasons to close or redo. In `why`, name what changed on main in one sentence.
