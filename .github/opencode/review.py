"""Send a data-only PR snapshot to Claude Code and publish via the existing review contract."""

import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

import run


MODEL = "claude-agent/ci-sonnet"
MAX_CONTEXT = 256 * 1024
MAX_SOURCE_FILE = 32 * 1024
MAX_RESULT = 512 * 1024


def request(event):
    source = event["workflow_run"]
    match = re.fullmatch(r"Review ([1-9][0-9]*) (opened|synchronize|ready_for_review|reopened|edited)",
                         source["display_title"])
    # The candidate can change its run name. Require GitHub's own association
    # with a same-repo PR, and use GitHub's run head rather than one from the name.
    if (not match or source["event"] != "pull_request" or source["conclusion"] != "success"
            or source["path"] != ".github/workflows/opencode-review.yml"
            or source["head_repository"]["full_name"] != run.REPO):
        return
    number = int(match[1])
    repo_id = event["repository"]["id"]
    if any(pr["number"] == number and pr["head"]["repo"]["id"] == repo_id for pr in source["pull_requests"]):
        return number, source["head_sha"], match[2] == "edited"


def changed_sources(base, head, budget):
    # Inspect Git objects only. Do not unpack trees, follow symlinks, or run filters.
    names = run.git("diff", "--name-only", "-z", "--no-renames", "--diff-filter=AMT", base, head, raw=True)
    sources = {}
    for name in names.split(b"\0")[:-1]:
        path = os.fsdecode(name)
        entry = run.git("--literal-pathspecs", "ls-tree", "-z", "-l", head, "--", path, raw=True)
        mode, kind, oid, size = entry.split(b"\t", 1)[0].split()
        if kind != b"blob" or mode not in (b"100644", b"100755") or int(size) > MAX_SOURCE_FILE:
            continue
        blob = run.git("cat-file", "blob", oid.decode(), raw=True)
        if b"\0" in blob:
            continue
        try:
            source = blob.decode()
        except UnicodeDecodeError:
            continue
        length = len(json.dumps({path: source}))
        if length <= budget:
            sources[path] = source
            budget -= length
    return sources


def prepare(number, head, retargeted, directory):
    run.CONTEXT = directory / "review-context"
    run.CONTEXT.mkdir(exist_ok=True)
    prepared = run.prepare_review(number, head, retargeted)
    if prepared is None:
        return False
    expected, merge_base = prepared
    data = {"pr": json.loads((run.CONTEXT / f"{number}.json").read_text()),
            "resolved_threads": (run.CONTEXT / "resolved.jsonl").read_text(),
            "diff": (run.CONTEXT / "pr.diff").read_bytes().decode(errors="replace")}
    budget = MAX_CONTEXT - len(json.dumps(data)) - 64
    run.check(budget >= 0, "PR review context is too large; review this PR manually.")
    data["changed_source"] = changed_sources(merge_base, head, budget)
    (directory / "review-input.json").write_text(json.dumps({"snapshot": expected, "data": data}))
    return True


def infer(data):
    token = os.environ.get("CLAUDE_CODE_OAUTH_TOKEN")
    run.check(token, "CLAUDE_CODE_OAUTH_TOKEN is required")
    settings = {
        "providers": {"claude-agent": {"models": {"ci-sonnet": {"name": "CI Sonnet", "modelID": "sonnet"}}}},
        "formatter": False, "lsp": False, "snapshots": False, "share": "disabled",
        "permissions": [run.permission("*", effect="deny")],
        "policies": [run.permission(action, effect="deny")
                     for action in ("tool.use", "plugin.use", "mcp.use", "skill.use")],
        "agents": {"ci": {"mode": "primary", "steps": 1}},
    }
    prompt = (Path(__file__).with_name("review.md").read_text()
              + "\n\nTrusted repository guidance:\n" + Path(__file__).parents[2].joinpath("AGENTS.md").read_text()
              + "\n\nPR data:\n" + json.dumps(data))
    with tempfile.TemporaryDirectory() as profile:
        cwd = Path(profile) / "work"
        cwd.mkdir()
        env = {key: os.environ[key] for key in ("PATH", "LANG", "LC_ALL") if key in os.environ}
        env.update(
            HOME=f"{profile}/home", CLAUDE_CONFIG_DIR=f"{profile}/claude",
            XDG_CONFIG_HOME=f"{profile}/config", XDG_DATA_HOME=f"{profile}/data",
            XDG_CACHE_HOME=f"{profile}/cache", XDG_STATE_HOME=f"{profile}/state",
            CLAUDE_CODE_OAUTH_TOKEN=token, OPENCODE_CONFIG_CONTENT=json.dumps(settings),
            OPENCODE_DISABLE_PROJECT_CONFIG="1", OPENCODE_CONFIG_PROJECT_DISABLE="1",
        )
        Path(env["HOME"]).mkdir()
        opencode = ["opencode", "--standalone"]
        subprocess.run([*opencode, "auth", "login", "claude-agent", "--method", "claude-login"],
                       cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        response = subprocess.run(
            [*opencode, "run", "--archived", "--format", "json", "--agent", "ci", "--model", MODEL],
            cwd=cwd, env=env, input=prompt.encode(), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True,
        )
    try:
        events = list(io.StringIO(response.stdout.decode()))
        run.check(not any(json.loads(line)["type"] == "tool_use" for line in events), "Unexpected tool use")
        return run.result_from_events(events)
    except (KeyError, ValueError) as error:
        raise ValueError("Claude Code did not return a complete JSON review") from error


def output(key, value):
    with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
        print(f"{key}={value}", file=stream)


def publish(number, head, directory):
    with (directory / "review-output" / "review-result.json").open("rb") as stream:
        raw = stream.read(MAX_RESULT + 1)
    run.check(len(raw) <= MAX_RESULT, "Oversized review result")
    payload = json.loads(raw)
    run.fields(payload, "run_id", "snapshot", "result")
    snapshot = payload["snapshot"]
    run.check(type(snapshot) is list and len(snapshot) == 3 and snapshot[0] == head
              and payload["run_id"] == os.environ["GITHUB_RUN_ID"],
              "Review result does not match the requested run and head")
    expected = tuple(snapshot)
    if not run.active_review(run.api(f"pulls/{number}"), expected):
        print("PR changed; discarding review.")
        return
    run.ensure_commit(expected[0])
    run.ensure_commit(expected[2])
    merge_base = run.git("merge-base", expected[2], expected[0])
    run.publish_review(number, expected, run.snapshot_marker(expected, merge_base), payload["result"])


def main(mode):
    directory = Path(os.environ["RUNNER_TEMP"])
    if mode == "infer":
        payload = json.loads((directory / "review-input.json").read_text())
        result = infer(payload["data"])
        (directory / "review-result.json").write_text(json.dumps({
            "run_id": os.environ["GITHUB_RUN_ID"], "snapshot": payload["snapshot"], "result": result,
        }))
        return
    target = request(json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text()))
    if target is None:
        return
    number, head, retargeted = target
    if mode == "reconcile":
        run.reconcile_reviews(number)
        output("number", number)
    elif mode == "prepare":
        if prepare(number, head, retargeted, directory):
            output("ready", "true")
    else:
        run.check(mode == "publish", "Unknown review stage")
        publish(number, head, directory)


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except subprocess.CalledProcessError as error:
        sys.exit(f"Command failed with exit code {error.returncode}")
    except (ValueError, KeyError) as error:
        sys.exit(str(error))
