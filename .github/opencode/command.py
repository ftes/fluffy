"""Authorize a maintainer command and publish only its validated changes."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote

import run


AGENT_COMMAND = re.compile(r"(?<![\w@/])/agent(?![\w/-])", re.I)
REQUEST_KEY = {
    "issue_comment": "comment",
    "pull_request_review_comment": "comment",
    "pull_request_review": "review",
    "issues": "issue",
}
BOT_EMAIL = f"219766164+{run.BOT}@users.noreply.github.com"
PROTECTED = (".git", ".github", ".opencode", ".claude", ".agents", "tmp/opencode")


def authorize(event, event_name):
    request = event.get(REQUEST_KEY.get(event_name)) or {}
    author = request.get("user") or {}
    sender = event["sender"]
    message = "\n".join(request.get(key) or "" for key in ("title", "body"))
    if (not AGENT_COMMAND.search(message) or request.get("author_association") not in run.MAINTAINERS
            or author.get("type") != "User" or sender["type"] != "User"):
        return None
    # Assignment may be done by someone other than the issue's author.
    for login in dict.fromkeys((sender["login"], author["login"])):
        permission = run.api(f"collaborators/{quote(login, safe='')}/permission")["permission"]
        if permission not in ("admin", "maintain", "write"):
            return None
    return request


def eligible(pr, default_branch):
    return run.local_pr(pr) and pr["state"] == "open" and pr["head"]["ref"] != default_branch


def target(event, event_name, default_branch, run_id):
    if not authorize(event, event_name):
        return {}
    item = event.get("pull_request") or event["issue"]
    number = item["number"]
    if "pull_request" in event or item.get("pull_request"):
        pr = run.api(f"pulls/{number}")
        repo = pr["head"]["repo"]
        if repo is None or repo["full_name"] != run.REPO:
            return {"fork": "true", "number": number} if event_name == "issue_comment" else {}
        if eligible(pr, default_branch):
            return {"run": "true", "pr": "true", "number": number, "branch": pr["head"]["ref"]}
        return {}
    return {"run": "true", "number": number, "branch": f"opencode/issue-{number}-{run_id}"}


def protected(path):
    name = Path(path).name
    return (any(path == entry or path.startswith(f"{entry}/") for entry in PROTECTED)
            or path.startswith("opencode.json") or name.endswith(".env") or ".env." in name)


def settings():
    config = run.config()
    config["agents"]["ci"]["steps"] = 50
    rules = config["permissions"]
    rules.append(run.permission("edit"))
    patterns = [pattern for path in PROTECTED for pattern in (path, f"{path}/*")]
    rules.extend(run.permission("edit", pattern, "deny") for pattern in (*patterns, "opencode.json*", "*.env", "*.env.*"))
    return config


def stage(parent):
    run.check(run.git("rev-parse", "HEAD") == parent, "The checkout moved during the command")
    run.git("add", "-A")
    paths = run.git("diff", "--cached", "--name-only", "--no-renames", "-z", raw=True)
    for path in os.fsdecode(paths).split("\0"):
        run.check(not protected(path), "Command cannot publish changes to workflow or agent configuration")
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


def one_line(value):
    subject = run.text(value, 200)
    run.check(len(subject.splitlines()) == 1 and subject == value, "Expected a one-line title")
    return subject


def recover(branch, marker, head=None):
    if head is None:
        sha = remote_head(branch)
    else:
        sha = run.git("log", "-1", "--format=%H", "--fixed-strings", f"--grep={marker}", head)
    if not sha:
        return None
    recorded = run.api(f"git/commits/{sha}")
    content, separator, trailer = recorded["message"].strip().rpartition("\n\n")
    run.check(separator and trailer == marker and recorded["author"]["email"] == BOT_EMAIL,
              "Existing publication does not belong to this request")
    title, separator, reply = content.partition("\n\n")
    run.check(separator, "Missing publication reply")
    return sha, one_line(title), run.text(reply, 12000)


def issue_pr(number, branch, base, publication, token):
    sha, title, reply = publication
    owner = run.REPO.split("/")[0]
    head = quote(f"{owner}:{branch}", safe="")
    matches = run.api(f"pulls?state=all&head={head}", token=token, paginate=True)
    if matches:
        pr = matches[0]
        run.check(len(matches) == 1 and run.local_pr(pr) and pr["head"]["sha"] == sha
                  and pr["base"]["ref"] == base and pr["user"]["login"] == run.BOT,
                  "Existing PR does not match the command publication")
    else:
        run.check(remote_head(branch) == sha, "Publication branch moved")
        pr = run.api("pulls", token=token, payload={"head": branch, "base": base, "title": title,
                                                   "body": f"{reply}\n\nRefs #{number}"})
        run.check(pr["head"]["sha"] == sha, "Publication branch moved during PR creation")
    return pr["html_url"]


def command(number, branch, default_branch, is_pr, run_id, prompt, request):
    path = f"pulls/{number}"
    parent = run.git("rev-parse", "HEAD")
    pr = run.api(path) if is_pr else None
    if is_pr and not matches_head(pr, default_branch, branch, parent):
        return
    marker = f"OpenCode-Command-Run: {run_id} {branch}"
    reply_marker = f"<!-- opencode-command: {run_id} -->"
    comments = f"issues/{number}/comments"
    if any((entry["user"] or {}).get("login") == run.BOT and (entry["body"] or "").endswith(reply_marker)
           for entry in run.api(comments, paginate=True)):
        return
    publication = recover(branch, marker, parent if is_pr else None)
    new_commit = False
    if publication:
        reply = publication[2]
    else:
        run.check(not run.git("status", "--porcelain"), "Toolchain setup left unpublished changes")
        run.context(number, is_pr=is_pr, item=pr)
        if is_pr:
            run.save("pr.diff", run.snapshot_diff(pr)[1])
            run.save("checks.json", run.gh("pr", "view", str(number), "--json", "statusCheckRollup"))
        run.save("request.json", {key: request.get(key) for key in ("title", "body", "path", "line", "diff_hunk")})
        result = run.agent(f"{prompt}\nContext: {run.CONTEXT}/{number}.json.",
                           '{"reply":"...", "title":"one-line commit title if you edited files; otherwise empty"}',
                           settings=settings())
        run.fields(result, "reply", "title")
        reply = run.text(result["reply"], 12000)
        run.check(not re.search(r"^OpenCode-Command-Run:", reply, re.M), "Reserved command trailer in output")
        changed = stage(parent)
        if changed:
            title = one_line(result["title"])
            sha = commit(title, f"{reply}\n\n{marker}", parent)
            publication = (sha, title, reply)
            new_commit = True
        else:
            run.check(result["title"] == "", "No changes to commit")
    with run.app_token() as token:
        if is_pr and not matches_head(run.api(path), default_branch, branch, parent):
            return
        if new_commit:
            push(branch, token, parent if is_pr else "")
        if publication and not is_pr:
            reply += f"\n\nOpened {issue_pr(number, branch, default_branch, publication, token)}."
        run.api(comments, token=token, payload={"body": f"{reply}\n\n{reply_marker}"})


def matches_head(pr, default_branch, branch, head):
    return eligible(pr, default_branch) and pr["head"]["ref"] == branch and pr["head"]["sha"] == head


def main(mode):
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    event_name = os.environ["GITHUB_EVENT_NAME"]
    default_branch = os.environ["DEFAULT_BRANCH"]
    run_id = os.environ["GITHUB_RUN_ID"]
    if mode == "gate":
        outputs = target(event, event_name, default_branch, run_id)
        with open(os.environ["GITHUB_OUTPUT"], "a") as file:
            for key, value in outputs.items():
                run.check("\n" not in str(value) and "\r" not in str(value), "Invalid gate output")
                print(f"{key}={value}", file=file)
        return
    run.check(mode == "command", "Expected command or gate")
    selected = target(event, event_name, default_branch, run_id)
    if selected.get("run") != "true" or selected["branch"] != os.environ["BRANCH"]:
        return
    run.CONTEXT.mkdir(parents=True, exist_ok=True)
    request = event[REQUEST_KEY[event_name]]
    command(selected["number"], selected["branch"], default_branch, selected.get("pr") == "true",
            run_id, Path(__file__).with_name("command.md").read_text(), request)


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except subprocess.CalledProcessError as error:
        sys.exit(f"Command failed with exit code {error.returncode}")
    except (ValueError, KeyError) as error:
        sys.exit(str(error))
