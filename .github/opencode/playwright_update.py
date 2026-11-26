"""Select, prepare and publish one PlaywrightEx release update."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys

import command
import publish
import run


LOCKFILES = ("mix.lock", "mix.lock.oldest", "integration/consumer/mix.lock")
HEX_LOCK = r'^  "playwright": \{:hex, :playwright_ex, "([^"]+)"'
GIT_LOCK = r'^  "playwright": \{:git, "[^"]+", "([0-9a-f]{40})"'
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?")
SHELL_COMMANDS = (
    "mix deps.update playwright", "mix playwright.install chromium", "mix fluffy.playwright_source",
    "mix usage_rules.sync --yes", "mix format", "mix test test/playwright_members_test.exs",
    "mix test test/dependency_floors_test.exs", "mix test --failed", "mix check",
)
TOOL_ENV = ("MIX_ENV", "MIX_HOME", "MIX_ARCHIVES", "MISE_DATA_DIR", "MISE_TRUSTED_CONFIG_PATHS",
            "MISE_YES", "PLAYWRIGHT_BROWSERS_PATH")


def version(value):
    run.check(isinstance(value, str) and VERSION.fullmatch(value), "Invalid PlaywrightEx release")
    return value


def branch_for(release):
    return f"opencode/playwright-ex-{version(release)}"


def plan(event, previous, current, legacy_head, head):
    # GitHub retains PR history after branch deletion. An open or merged PR always
    # handles the release, and scheduled runs also honor a maintainer's closed PR.
    prs = previous + current
    if any(pr["state"] == "open" or pr["merged_at"] for pr in prs):
        return "skip", "The release already has an open or merged PR."
    if legacy_head or (head and any(pr["head"]["sha"] == head for pr in current)):
        return "skip", "Delete the retained update branch before retrying a closed PR."
    if head:
        return "recover", "Resume the pushed update."
    if prs and event != "workflow_dispatch":
        return "skip", "A scheduled run does not retry a closed update."
    return "new", "Prepare the update."


def check_release(event):
    lock = Path("mix.lock").read_text()
    locked_hex, locked_git = re.search(HEX_LOCK, lock, re.M), re.search(GIT_LOCK, lock, re.M)
    run.check(locked_hex or locked_git, "Cannot read PlaywrightEx from mix.lock")
    response = run.capture("curl", "-fsSL", "--retry", "3", "https://hex.pm/api/packages/playwright_ex")
    release = version(json.loads(response)["latest_version"])
    previous = locked_hex[1] if locked_hex else locked_git[1]
    if locked_hex:
        newer = release != previous
    else:
        comparison = json.loads(run.gh("api", f"repos/ftes/playwright_ex/compare/{previous}...v{release}"))
        newer = comparison["status"] in ("ahead", "identical")
    if not newer:
        return {"mode": "skip"}, f"Hex release {release} does not update the locked {previous}."

    branch = branch_for(release)
    legacy = f"claude/playwright-ex-{release}"
    mode, note = plan(event, publish.pull_requests(legacy), publish.pull_requests(branch),
                      publish.remote_head(legacy), publish.remote_head(branch))
    return {"mode": mode, "from": previous, "release": release, "base-sha": run.git("rev-parse", "HEAD")}, note


def settings():
    config = command.settings()
    config["agents"]["ci"]["steps"] = 150
    config["permissions"].extend(run.permission("shell", cmd) for cmd in SHELL_COMMANDS)
    return config


def validate_version(release, revision=None):
    for name in (*LOCKFILES, "mix.exs"):
        content = (run.git("show", f"{revision}:{name}", raw=True).decode()
                   if revision else Path(name).read_text())
        pattern = HEX_LOCK if name != "mix.exs" else r'^[ \t]*\{:playwright, "~> ([^"]+)", hex: :playwright_ex\},?$'
        match = re.search(pattern, content, re.M)
        run.check(match and match[1] == release, f"Expected PlaywrightEx {release} in {name}")


def recover(branch, release, parent):
    sha = publish.remote_head(branch)
    run.check(sha, "The unfinished update branch disappeared")
    record = run.api(f"git/commits/{sha}")
    title = f"Update PlaywrightEx to {release}"
    content, separator, marker = record["message"].strip().rpartition("\n\n")
    subject, paragraph, body = content.partition("\n\n")
    run.check(separator and paragraph and marker == f"OpenCode-PlaywrightEx: {release}" and subject == title
              and record["author"]["email"] == publish.BOT_EMAIL and len(record["parents"]) == 1,
              "Existing branch is not a recoverable PlaywrightEx update")
    run.ensure_commit(sha)
    run.git("merge-base", "--is-ancestor", record["parents"][0]["sha"], parent)
    validate_version(release, sha)
    return sha, run.text(body, 12000)


def open_draft(branch, base, release, sha, body, token):
    prs = publish.pull_requests(branch, token=token)
    # A historical closed PR at another SHA is not this publication. An open PR
    # is always live, so a mismatched one is treated as a conflict.
    existing = [pr for pr in prs if pr["state"] == "open" or pr["merged_at"] or pr["head"]["sha"] == sha]
    if existing:
        pr = existing[0]
        run.check(len(existing) == 1 and pr["head"]["sha"] == sha and run.local_pr(pr)
                  and pr["base"]["ref"] == base and pr["user"]["login"] == run.BOT,
                  "Existing PR does not match the update")
    else:
        run.check(publish.remote_head(branch) == sha, "Publication branch moved")
        pr = run.api("pulls", token=token, payload={
            "head": branch, "base": base, "title": f"Update PlaywrightEx to {release}",
            "body": body, "draft": True,
        })
        run.check(pr["head"]["sha"] == sha, "Publication branch moved during PR creation")
    return pr["html_url"], pr["state"]


def update(mode, previous, release, base, parent):
    branch = branch_for(release)
    run.check(run.git("rev-parse", "HEAD") == parent, "Unexpected update base")
    if mode == "recover":
        sha, body = recover(branch, release, parent)
    else:
        run.check(mode == "new", "Unexpected update mode")
        run.check(not run.git("status", "--porcelain"), "Toolchain setup left unpublished changes")
        prompt = Path(__file__).with_name("playwright_update.md").read_text()
        result = run.agent(f"{prompt}\n\nFrom: {previous}\nTo: {release}\n",
                           '{"body":"PR body describing the update and check results"}',
                           settings=settings(), tool_env=TOOL_ENV)
        run.fields(result, "body")
        body = run.text(result["body"], 12000)
        run.check(publish.stage(parent, allow_generated_skills=True), "No update to publish")
        sha = publish.commit(f"Update PlaywrightEx to {release}", f"{body}\n\nOpenCode-PlaywrightEx: {release}", parent)
        validate_version(release, sha)
    with run.app_token() as token:
        if mode == "new":
            publish.push(branch, token, "")
        url, state = open_draft(branch, base, release, sha, body, token)
        print(f"{state}: {url}")


def main(mode):
    if mode == "check":
        values, note = check_release(os.environ["GITHUB_EVENT_NAME"])
        print(note)
        with open(os.environ["GITHUB_OUTPUT"], "a") as file:
            for key, value in values.items():
                print(f"{key}={value}", file=file)
        return
    run.check(mode == "update", "Expected check or update")
    update(os.environ["MODE"], os.environ["PLAYWRIGHT_FROM"], os.environ["PLAYWRIGHT_TO"],
           os.environ["BASE_BRANCH"], os.environ["BASE_SHA"])


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except subprocess.CalledProcessError as error:
        sys.exit(f"Command failed with exit code {error.returncode}")
    except (ValueError, KeyError) as error:
        sys.exit(str(error))
