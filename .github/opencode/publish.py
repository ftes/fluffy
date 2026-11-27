"""Git operations shared by OpenCode publishers."""

import os
from pathlib import Path
import subprocess
from urllib.parse import quote

import run


BOT_EMAIL = f"219766164+{run.BOT}@users.noreply.github.com"
PROTECTED = (".git", ".github", ".opencode", ".claude", ".agents", "tmp/opencode")


def protected(path):
    name = Path(path).name
    return (any(path == entry or path.startswith(f"{entry}/") for entry in PROTECTED)
            or path.startswith("opencode.json") or name.endswith(".env") or ".env." in name)


def stage(parent):
    run.check(run.git("rev-parse", "HEAD") == parent, "The checkout moved during the run")
    run.git("add", "-A")
    paths = run.git("diff", "--cached", "--name-only", "--no-renames", "-z", raw=True)
    for path in os.fsdecode(paths).split("\0"):
        run.check(not protected(path), "Automation cannot publish changes to workflow or agent configuration")
    return bool(paths)


def commit(title, body, parent):
    run.git("-c", f"user.name={run.BOT}", "-c", f"user.email={BOT_EMAIL}", "-c", "commit.gpgsign=false",
            "commit", "--cleanup=verbatim", "-m", title, "-m", body)
    run.check(run.git("rev-parse", "HEAD^") == parent, "Unexpected commit parent")
    return run.git("rev-parse", "HEAD")


def remote_head(branch):
    ref = f"refs/heads/{branch}"
    try:
        listing = run.git("ls-remote", "--exit-code", "--refs", "origin", ref)
    except subprocess.CalledProcessError as error:
        if error.returncode == 2:
            return None
        raise
    sha, remote_ref = listing.split("\t")
    run.check(remote_ref == ref, "Unexpected remote branch")
    return sha


def push(branch, token, expected):
    ref = f"refs/heads/{branch}"
    run.git("check-ref-format", ref)
    run.git("push", f"--force-with-lease={ref}:{expected}", f"https://github.com/{run.REPO}.git", f"HEAD:{ref}",
            env=run.git_http_env(token))


def pull_requests(branch, token=None):
    owner = run.REPO.split("/")[0]
    head = quote(f"{owner}:{branch}", safe="")
    return run.api(f"pulls?state=all&head={head}", token=token, paginate=True)
