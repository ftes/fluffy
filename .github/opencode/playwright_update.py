"""Select, prepare and publish one PlaywrightEx release update."""

import io
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import zipfile

import publish
import run


LOCKFILES = ("mix.lock", "mix.lock.oldest", "integration/consumer/mix.lock")
HEX_LOCK = r'^  "playwright": \{:hex, :playwright_ex, "([^"]+)"'
GIT_LOCK = r'^  "playwright": \{:git, "[^"]+", "([0-9a-f]{40})"'
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?")
INVENTORY = "test/support/playwright_members.ex"
DEPENDENCY = r'^[ \t]*\{:playwright, "~> ([^"]+)", hex: :playwright_ex\},?$'
GIT_DEPENDENCY = r'^[ \t]*\{:playwright, github: "ftes/playwright_ex"[^}\n]*\},?$'
UPDATE_FILES = (
    *LOCKFILES, "mix.exs", "CHANGELOG.md", "docs/installation.md", "usage-rules.md", INVENTORY,
    ".agents/skills/playwright/SKILL.md",
    ".agents/skills/playwright/references/playwright/playwright.md",
)
MAX_ARTIFACT = 512 * 1024
CHECKS = "\n\nChecks: `mix check` and the oldest lockfile's `mix deps.get --check-locked` passed."


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
    head = publish.remote_head(branch)
    mode, note = plan(event, publish.pull_requests(legacy), publish.pull_requests(branch),
                      publish.remote_head(legacy), head)
    return {"mode": mode, "from": previous, "release": release, "base-sha": run.git("rev-parse", "HEAD"),
            "expected-head": head or ""}, note


def settings():
    config = run.config()
    config["policies"].extend(
        run.permission("tool.use", f"{tool}:*", "deny") for tool in ("shell", "edit", "external_directory")
    )
    return config


def validate_version(release, files):
    for name in (*LOCKFILES, "mix.exs"):
        match = re.search(HEX_LOCK if name in LOCKFILES else DEPENDENCY, files[name], re.M)
        run.check(match and match[1] == release, f"Expected PlaywrightEx {release} in {name}")


def identity(kind, run_id, parent, release):
    return {"kind": kind, "repository": run.REPO, "run": run_id, "base": parent, "release": release}


def write_artifact(kind, run_id, parent, release, **data):
    info = identity(kind, run_id, parent, release) | data
    result = json.dumps(info, ensure_ascii=False).encode()
    run.check(len(result) <= MAX_ARTIFACT, "Update data exceeds the artifact size limit")
    (Path(os.environ["RUNNER_TEMP"]) / f"{kind}.json").write_bytes(result)


def read_artifact(artifact_id, kind, run_id, parent, release):
    run.check(re.fullmatch(r"[0-9]+", artifact_id) and re.fullmatch(r"[0-9]+", run_id), "Invalid artifact identity")
    record = run.api(f"actions/artifacts/{artifact_id}")
    workflow = record["workflow_run"]
    run.check(not record["expired"] and record["size_in_bytes"] <= MAX_ARTIFACT
              and re.fullmatch(rf"playwright-{kind}-[0-9]+", record["name"])
              and str(workflow["id"]) == run_id and workflow["head_sha"] == parent
              and workflow["repository_id"] == workflow["head_repository_id"],
              "Artifact is not from the selected update run and base")
    archive = run.gh("api", f"repos/{run.REPO}/actions/artifacts/{artifact_id}/zip", raw=True)
    run.check(len(archive) <= MAX_ARTIFACT, "Oversized artifact archive")
    with zipfile.ZipFile(io.BytesIO(archive)) as contents:
        name = f"{kind}.json"
        run.check(contents.namelist() == [name], "Unexpected artifact files")
        entry = contents.getinfo(name)
        mode = stat.S_IFMT(entry.external_attr >> 16)
        run.check(mode in (0, stat.S_IFREG) and entry.file_size <= MAX_ARTIFACT, "Invalid artifact entry")
        data = json.loads(contents.read(entry))
    expected = identity(kind, run_id, parent, release)
    run.fields(data, *expected, "body", "patch" if kind == "proposal" else "files")
    run.check(all(data[key] == value for key, value in expected.items()), "Artifact metadata does not match")
    return data


def blob(revision, path):
    run.check(run.git("ls-tree", revision, "--", path).startswith("100644 blob "), f"Not a regular file: {path}")
    return run.git("show", f"{revision}:{path}", raw=True).decode()


def changed_files(parent, revision):
    paths = os.fsdecode(run.git("diff", "--name-only", "-z", "--no-renames", parent, revision, raw=True))
    names = paths.split("\0")[:-1]
    run.check(set(names) <= set(UPDATE_FILES), "Unexpected changed paths in the update")
    return {name: blob(revision, name) for name in names}


def checked_files(data, release):
    files = data["files"]
    run.check(type(files) is dict and set(LOCKFILES + ("mix.exs", "CHANGELOG.md")) <= files.keys()
              and files.keys() <= set(UPDATE_FILES),
              "Unexpected update paths or missing required files")
    run.check(all(type(value) is str and "\0" not in value for value in files.values()),
              "Update files must be text")
    validate_version(release, files)
    return files, run.text(data["body"], 12000)


def stage_replacements(parent, files):
    # Use a fresh Git index. No patch paths, modes, hooks, worktree files or Git
    # configuration from another job participate in staging.
    run.check(run.git("rev-parse", "HEAD") == parent, "Unexpected update base")
    for name, content in files.items():
        blob(parent, name)
        oid = run.git("hash-object", "-w", "--stdin", input=content)
        run.git("update-index", "--cacheinfo", f"100644,{oid},{name}")


def propose(previous, release, parent, run_id):
    run.check(run.git("rev-parse", "HEAD") == parent, "Unexpected update base")
    old_ref = previous if re.fullmatch(r"[0-9a-f]{40}", previous) else f"v{version(previous)}"
    upstream = json.loads(run.gh("api", f"repos/ftes/playwright_ex/compare/{old_ref}...v{version(release)}"))
    run.CONTEXT.mkdir(parents=True, exist_ok=True)
    run.save("playwright-upstream.json", [
        {key: item.get(key) for key in ("filename", "status", "patch")} for item in upstream["files"]
        if item["filename"] == "CHANGELOG.md" or item["filename"].startswith("lib/")
    ])
    prompt = Path(__file__).with_name("playwright_update.md").read_text()
    result = run.agent(f"{prompt}\n\nFrom: {previous}\nTo: {release}\n",
                       '{"patch":"unified diff for the member inventory only, or empty", "body":"short PR summary"}',
                       settings=settings())
    run.fields(result, "patch", "body")
    run.check(type(result["patch"]) is str, "Expected a text inventory patch")
    write_artifact("proposal", run_id, parent, release, patch=result["patch"], body=run.text(result["body"], 12000))


def apply_inventory(patch):
    run.check(type(patch) is str and "\0" not in patch, "Expected a text inventory patch")
    if not patch:
        return
    run.git("apply", "--cached", "-", input=patch)
    changed = run.git("diff", "--cached", "--raw", "--no-renames", "--no-abbrev", "-z", raw=True)
    record = rb":100644 100644 [0-9a-f]{40} [0-9a-f]{40} M\x00" + INVENTORY.encode() + b"\x00"
    run.check(re.fullmatch(record, changed), "The proposal may only modify the regular inventory file")
    run.git("checkout-index", "--force", "--", INVENTORY)


def update_files(previous, release):
    exists = Path("mix.exs")
    config = exists.read_text()
    pattern = GIT_DEPENDENCY if re.fullmatch(r"[0-9a-f]{40}", previous) else DEPENDENCY
    config, matches = re.subn(pattern, f'      {{:playwright, "~> {release}", hex: :playwright_ex}},', config, flags=re.M)
    run.check(matches == 1, "Cannot replace the PlaywrightEx dependency")
    exists.write_text(config)
    for name in ("docs/installation.md", "usage-rules.md"):
        path = Path(name)
        original = path.read_text()
        updated = original.replace(f"~> {previous}", f"~> {release}")
        if updated != original:
            path.write_text(updated)
    changelog = Path("CHANGELOG.md")
    changed, matches = re.subn(r"^## Unreleased\n", f"## Unreleased\n\n- Requires PlaywrightEx {release}.\n",
                               changelog.read_text(), count=1, flags=re.M)
    run.check(matches == 1, "CHANGELOG.md needs an Unreleased section")
    changelog.write_text(changed)


def verify(artifact, previous, release, parent, run_id):
    run.check(run.git("rev-parse", "HEAD") == parent, "Unexpected update base")
    proposal = read_artifact(artifact, "proposal", run_id, parent, release)
    body = run.text(proposal["body"], 12000)
    apply_inventory(proposal["patch"])
    update_files(previous, release)
    subprocess.run(["mix", "deps.update", "playwright"], check=True)
    newest = Path("mix.lock").read_text()
    entry = re.search(HEX_LOCK + r"[^\n]*", newest, re.M)
    run.check(entry and entry[1] == release, "Hex did not resolve the selected release")
    oldest = Path("mix.lock.oldest")
    floor, matches = re.subn(HEX_LOCK + r"[^\n]*", lambda _: entry[0], oldest.read_text(), flags=re.M)
    run.check(matches == 1, "Cannot move the oldest PlaywrightEx lock")
    oldest.write_text(floor)
    # Exercise the oldest lock without changing the checked-out dependencies.
    try:
        Path("mix.lock").write_text(floor)
        subprocess.run(["mix", "deps.get", "--check-locked"], check=True,
                       env=dict(os.environ, MIX_DEPS_PATH="tmp/playwright-oldest-deps"))
    finally:
        Path("mix.lock").write_text(newest)
    subprocess.run(["mix", "deps.update", "playwright"], cwd="integration/consumer", check=True)
    for args in (("assets.build",), ("playwright.install", "chromium"), ("fluffy.playwright_source",),
                 ("usage_rules.sync", "--yes"), ("format",), ("check",)):
        subprocess.run(["mix", *args], check=True)
    run.git("add", "-A")
    # Export only regular changed text files, never checkout or runner state.
    tree = run.git("write-tree")
    files = changed_files(parent, tree)
    checked_files({"files": files, "body": body}, release)
    write_artifact("verified", run_id, parent, release, files=files, body=body)


def recover(branch, release, parent, sha):
    run.check(re.fullmatch(r"[0-9a-f]{40}", sha) and publish.remote_head(branch) == sha,
              "The unfinished update branch moved")
    record = run.api(f"git/commits/{sha}")
    title = f"Update PlaywrightEx to {release}"
    content, separator, marker = record["message"].strip().rpartition("\n\n")
    subject, paragraph, body = content.partition("\n\n")
    provenance = re.fullmatch(rf"OpenCode-PlaywrightEx-Isolated: {re.escape(release)} ([0-9]+) ([0-9]+)", marker)
    run.check(separator and paragraph and provenance and subject == title
              and record["author"]["email"] == publish.BOT_EMAIL and len(record["parents"]) == 1,
              "Existing branch is not a recoverable PlaywrightEx update")
    original = record["parents"][0]["sha"]
    workflow = run.api(f"actions/runs/{provenance[1]}")
    run.check(workflow["path"] == ".github/workflows/playwright-ex-update.yml"
              and workflow["head_sha"] == original and workflow["event"] in ("schedule", "workflow_dispatch"),
              "Unexpected updater run provenance")
    run.ensure_commit(sha)
    run.git("merge-base", "--is-ancestor", original, parent)
    files, summary = checked_files(read_artifact(provenance[2], "verified", provenance[1], original, release), release)
    run.check(files == changed_files(original, sha) and body == summary + CHECKS,
              "The branch does not match its verified update")
    return body


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


def publish_update(mode, release, base, parent, run_id, artifact, expected_head):
    branch = branch_for(release)
    run.check(run.git("rev-parse", "HEAD") == parent, "Unexpected update base")
    if mode == "recover":
        sha = expected_head
        body = recover(branch, release, parent, sha)
    else:
        run.check(mode == "new" and not expected_head, "Unexpected update mode or head")
        files, body = checked_files(read_artifact(artifact, "verified", run_id, parent, release), release)
        stage_replacements(parent, files)
        body += CHECKS
        marker = f"OpenCode-PlaywrightEx-Isolated: {release} {run_id} {artifact}"
        sha = publish.commit(f"Update PlaywrightEx to {release}", f"{body}\n\n{marker}", parent)
    run.check(publish.remote_head(base) == parent, "The base branch moved; start a fresh update run")
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
    release, parent, run_id = version(os.environ["PLAYWRIGHT_TO"]), os.environ["BASE_SHA"], os.environ["GITHUB_RUN_ID"]
    if mode == "propose":
        propose(os.environ["PLAYWRIGHT_FROM"], release, parent, run_id)
    elif mode == "verify":
        verify(os.environ["ARTIFACT_ID"], os.environ["PLAYWRIGHT_FROM"], release, parent, run_id)
    else:
        run.check(mode == "publish", "Expected check, propose, verify, or publish")
        publish_update(os.environ["MODE"], release, os.environ["BASE_BRANCH"], parent, run_id,
                       os.environ["ARTIFACT_ID"], os.environ["EXPECTED_HEAD"])


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except subprocess.CalledProcessError as error:
        sys.exit(f"Command failed with exit code {error.returncode}")
    except (ValueError, KeyError, zipfile.BadZipFile) as error:
        sys.exit(str(error))
