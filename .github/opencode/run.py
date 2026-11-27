"""Run a read-only OpenCode PR review and publish its validated verdict."""

import base64
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.request


BOT = "opencode-agent[bot]"
LEGACY_BOT = "claude[bot]"
REVIEW_BOTS = (BOT, LEGACY_BOT)
MAINTAINERS = ("OWNER", "MEMBER", "COLLABORATOR")
REPO = os.environ.get("GITHUB_REPOSITORY")
CONTEXT = Path("tmp/opencode")
DIFF_ARGS = ("diff", "--no-ext-diff", "--no-textconv", "--binary")
READ_TOOLS = ("read", "glob", "grep")
SAFE_ENV = ("PATH", "HOME", "USER", "LANG", "LC_ALL", "TMPDIR")


def check(condition, message):
    if not condition:
        raise ValueError(message)


def capture(*args, raw=False, **kwargs):
    if raw:
        return subprocess.check_output(args, **kwargs)
    return subprocess.check_output(args, text=True, **kwargs).strip()


def git(*args, **kwargs):
    return capture("git", "-c", "core.hooksPath=/dev/null", *args, **kwargs)


def gh(*args, token=None, **kwargs):
    env = dict(os.environ, GH_REPO=REPO)
    if token is not None:
        env["GH_TOKEN"] = token
    return capture("gh", *args, env=env, **kwargs)


def api(path, *, token=None, payload=None, paginate=False, method="POST"):
    args = ["api", f"repos/{REPO}/{path}"]
    if paginate:
        args += ["--paginate", "--slurp"]
    if payload is not None:
        args += ["--method", method, "--input", "-"]
    data = json.loads(gh(*args, token=token, input=json.dumps(payload) if payload is not None else None))
    return [item for page in data for item in page] if paginate else data


@contextlib.contextmanager
def app_token():
    # Same exchange as the OpenCode GitHub App integration. Only the publisher gets the token.
    def exchange(url, bearer, method="GET"):
        # OpenCode's edge rejects urllib's default Python-urllib user agent.
        request = urllib.request.Request(url, method=method, headers={
            "Authorization": f"Bearer {bearer}",
            "User-Agent": "opencode",
        })
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)

    oidc = exchange(os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"] + "&audience=opencode-github-action",
                    os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"])["value"]
    token = exchange("https://api.opencode.ai/exchange_github_app_token", oidc, "POST")["token"]
    print(f"::add-mask::{token}", flush=True)
    try:
        yield token
    finally:
        gh("api", "--method", "DELETE", "/installation/token", "--silent", token=token)


def trusted(comment):
    user = comment.get("user") or {}
    if not user:
        return False
    if user.get("type") == "Bot":
        return user.get("login") in REVIEW_BOTS
    return comment["author_association"] in MAINTAINERS


def save(name, value):
    path = CONTEXT / name
    if isinstance(value, bytes):
        path.write_bytes(value)
    else:
        path.write_text(value if isinstance(value, str) else json.dumps(value, ensure_ascii=False))


def context(number, *, is_pr=True, item=None):
    if item is None:
        item = api(f"{'pulls' if is_pr else 'issues'}/{number}")
    # PR titles/descriptions and diffs are task data. The only discussion we collect is trusted.
    data = {key: item.get(key) for key in ("number", "title", "body", "state", "html_url")}
    paths = [f"issues/{number}/comments"]
    if is_pr:
        data.update(head=item["head"]["sha"], base=item["base"]["ref"], branch=item["head"]["ref"])
        paths += [f"pulls/{number}/reviews", f"pulls/{number}/comments"]
    data["discussion"] = [
        {key: comment.get(key) for key in ("id", "in_reply_to_id", "body", "path", "line",
                                          "state", "submitted_at", "created_at")}
        | {"author": comment["user"]["login"]}
        for path in paths for comment in api(path, paginate=True) if trusted(comment) and comment.get("body")
    ]
    save(f"{number}.json", data)
    return item


def local_pr(pr):
    head = pr["head"]
    return (head["repo"] is not None and head["repo"]["full_name"] == REPO
            and not head["ref"].startswith("renovate/"))


def permission(action, resource="*", effect="allow"):
    return {"action": action, "resource": resource, "effect": effect}


def config():
    rules = [permission("*", effect="deny"), *(permission(tool) for tool in READ_TOOLS)]
    for pattern in (".git", ".git/*", "*.env", "*.env.*"):
        rules.append(permission("read", pattern, "deny"))
    return {
        "share": "disabled",
        "formatter": False,
        "lsp": False,
        "snapshots": False,
        "permissions": rules,
        "policies": [permission(action, effect="deny") for action in ("plugin.use", "mcp.use", "skill.use")],
        "agents": {"ci": {"mode": "primary", "steps": 80}},
    }


def result_from_events(events):
    chunks = []
    finished = False
    for line in events:
        event = json.loads(line)
        if event["type"] == "error":
            error = event.get("error", {})
            raise ValueError(f"OpenCode failed: {error.get('type', 'unknown error')}: {error.get('message', '')}")
        if event["type"] == "step_start":
            chunks = []
            finished = False
        if event["type"] == "text":
            chunks.append(event["part"]["text"])
        if event["type"] == "step_finish":
            finished = event["part"]["reason"] == "stop"
    check(finished, "OpenCode did not finish its final answer")
    return json.loads("".join(chunks))


def agent(prompt, shape, *, settings=None, tool_env=()):
    with tempfile.TemporaryDirectory() as tmp:
        env = {key: os.environ[key] for key in (*SAFE_ENV, *tool_env) if key in os.environ}
        env.update(
            XDG_CONFIG_HOME=f"{tmp}/config", XDG_DATA_HOME=f"{tmp}/data",
            XDG_CACHE_HOME=f"{tmp}/cache", XDG_STATE_HOME=f"{tmp}/state",
            OPENCODE_API_KEY=os.environ["OPENCODE_API_KEY"],
            OPENCODE_CONFIG_CONTENT=json.dumps(settings if settings is not None else config()),
            OPENCODE_DISABLE_PROJECT_CONFIG="1",
            OPENCODE_CONFIG_PROJECT_DISABLE="1",
        )
        message = (
            f"{prompt}\n\n"
            "Do not publish anything. "
            "End with exactly one JSON object, without Markdown fences or prose, in this shape:\n"
            f"{shape}"
        )
        events_path = Path(tmp) / "events"
        with events_path.open("w") as events:
            run = subprocess.run(
                ["opencode", "--standalone", "run", "--archived", "--format", "json",
                 "--agent", "ci", "--model", "opencode-go/kimi-k3.1-pro", message],
                env=env, stdout=events, check=False,
            )
        with events_path.open() as events:
            result = result_from_events(events)
        run.check_returncode()
        return result


def fields(value, *keys):
    check(type(value) is dict and value.keys() == set(keys), f"Expected fields: {', '.join(keys)}")


def text(value, limit):
    check(type(value) is str and len(value) <= limit and "\0" not in value and value.strip(), "Invalid output text")
    check(not re.search(r"<!--\s*(?:(?:claude|opencode)-review|opencode-command):", value),
          "Reserved review marker or command marker in output")
    return value.strip()


def patch_lines(patch):
    left = right = 0
    valid = set()
    for line in patch.split("\n"):
        if line.startswith("@@"):
            match = re.match(r"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
            if match:
                left, right = map(int, match.groups())
        elif line.startswith("-"):
            valid.add(("LEFT", left))
            left += 1
        elif line.startswith("+"):
            valid.add(("RIGHT", right))
            right += 1
        elif line.startswith(" "):
            valid.add(("RIGHT", right))
            left += 1
            right += 1
    return valid


def snapshot(pr):
    return pr["head"]["sha"], pr["base"]["ref"], pr["base"]["sha"]


def ensure_commit(sha):
    try:
        git("cat-file", "-e", f"{sha}^{{commit}}")
    except subprocess.CalledProcessError:
        git("fetch", "--quiet", "--no-tags", "origin", sha, env=git_http_env(os.environ["GH_TOKEN"]))


def snapshot_diff(pr):
    head, _, base = snapshot(pr)
    ensure_commit(base)
    ensure_commit(head)
    merge_base = git("merge-base", base, head)
    return merge_base, git(*DIFF_ARGS, merge_base, head, raw=True)


def reviewed_diff(marker):
    head, merge_base, _, _ = marker
    ensure_commit(head)
    ensure_commit(merge_base)
    return git(*DIFF_ARGS, merge_base, head, raw=True)


def review_marker(body):
    match = re.search(
        r"<!-- (?:claude|opencode)-review: ([0-9a-f]{40}) ([0-9a-f]{40})"
        r"(?: ([0-9a-f]{64}) ([0-9a-f]{40}))? -->\s*$", body or "",
    )
    return match.groups() if match else None


def previous_review(number):
    # New reviews carry the marker themselves; continue to recognize historical summary comments.
    items = api(f"issues/{number}/comments", paginate=True) + api(f"pulls/{number}/reviews", paginate=True)
    for item in sorted(items, key=lambda entry: entry.get("submitted_at") or entry.get("created_at") or "", reverse=True):
        if item.get("state") == "PENDING" or not item["user"]:
            continue
        if item["user"]["type"] == "Bot" and item["user"]["login"] in REVIEW_BOTS:
            marker = review_marker(item["body"])
            if marker:
                return marker, item.get("state") != "DISMISSED"
    return None, False


def active_review(pr, expected):
    return local_pr(pr) and pr["state"] == "open" and not pr["draft"] and snapshot(pr) == expected


def dismiss_review(number, review_id, token, message):
    path = f"pulls/{number}/reviews/{review_id}"
    if api(path)["state"] not in ("APPROVED", "CHANGES_REQUESTED"):
        return
    try:
        api(f"{path}/dismissals", token=token, method="PUT", payload={"message": message})
    except subprocess.CalledProcessError:
        if api(path)["state"] != "DISMISSED":  # GitHub may dismiss it concurrently.
            raise


STALE_VERDICT = "The PR snapshot changed. This verdict applies only to the previous snapshot."
REPLACED_VERDICT = "OpenCode approved the current snapshot. Existing review threads still need resolution."


def legacy_verdict(item):
    user = item["user"] or {}
    if user.get("type") != "Bot" or user.get("login") != LEGACY_BOT:
        return False
    body = (item["body"] or "").strip()
    if item["state"] == "APPROVED":
        return body == "Verdict: OK to merge."
    return item["state"] == "CHANGES_REQUESTED" and bool(re.fullmatch(
        r"Verdict: Issues found: \d+ blocking, \d+ non-blocking\.", body,
    ))


def last_retarget(number, ref):
    # Read the timeline when needed. A base edit on a draft has no review job of its own.
    event = json.loads(gh(
        "api", "graphql", "-f", f"owner={REPO.split('/')[0]}", "-f", f"name={REPO.split('/')[1]}",
        "-F", f"pr={number}", "-f",
        """query=query($owner: String!, $name: String!, $pr: Int!) {
          repository(owner: $owner, name: $name) { pullRequest(number: $pr) {
            timelineItems(last: 1, itemTypes: [BASE_REF_CHANGED_EVENT]) {
              nodes { ... on BaseRefChangedEvent { createdAt currentRefName } }
            }
          } }
        }""",
        "--jq", ".data.repository.pullRequest.timelineItems.nodes[0] // null",
    ))
    return event["createdAt"] if event and event["currentRefName"] == ref else None


def reconcile_reviews(number, token=None):
    pr = api(f"pulls/{number}")
    expected = snapshot(pr)
    if not active_review(pr, expected):
        return
    head, ref, base = expected
    target = hashlib.sha256(ref.encode()).hexdigest()
    items = api(f"pulls/{number}/reviews", paginate=True)
    stale = {}
    current_verdict = None
    current_diff = None
    # GitHub lists reviews chronologically; the last verdict for this diff wins.
    for item in items:
        user = item["user"] or {}
        if item["state"] not in ("APPROVED", "CHANGES_REQUESTED") or user.get("login") != BOT:
            continue
        marker = review_marker(item["body"])
        if marker and marker[2]:
            if (marker[0], *marker[2:]) == (head, target, base):
                current_verdict = item["state"]
                continue
            if marker[2:] == (target, base):
                try:
                    if current_diff is None:
                        current_diff = snapshot_diff(pr)[1]
                    if reviewed_diff(marker) == current_diff:
                        current_verdict = item["state"]
                        continue
                except subprocess.CalledProcessError:
                    print("Could not verify unchanged diff for the previous review.")
            stale[item["id"]] = STALE_VERDICT
    # Main's ruleset dismisses approvals when the diff changes. A retarget can keep
    # a legacy approval, whose verdict did not identify the base.
    legacy = [item for item in items if legacy_verdict(item)]
    legacy_approvals = [item for item in legacy if item["state"] == "APPROVED"]
    retargeted_at = last_retarget(number, ref) if legacy_approvals else None
    for item in legacy:
        if current_verdict == "APPROVED" and item["state"] == "CHANGES_REQUESTED":
            stale[item["id"]] = REPLACED_VERDICT
    for item in legacy_approvals:
        if retargeted_at and item.get("submitted_at") and retargeted_at >= item["submitted_at"]:
            stale[item["id"]] = STALE_VERDICT
    if stale:
        with (contextlib.nullcontext(token) if token else app_token()) as credential:
            if active_review(api(f"pulls/{number}"), expected):
                for review_id, message in stale.items():
                    dismiss_review(number, review_id, credential, message)


def review(number, head, prompt, retargeted=False):
    pr = api(f"pulls/{number}")
    expected = snapshot(pr)
    if expected[0] != head or not active_review(pr, expected):
        return
    author = pr["user"]["login"]
    check(pr["user"]["type"] != "Bot" or author in REVIEW_BOTS, "Unapproved PR author")
    base, full = snapshot_diff(pr)
    target = hashlib.sha256(expected[1].encode()).hexdigest()
    marker = (head, base, target, expected[2])
    previous, previous_active = previous_review(number)
    if previous_active and previous == marker:
        return
    depth = "full"
    if previous and not retargeted and previous[2:] == marker[2:]:
        old_head, old_base, _, _ = previous
        try:
            old = reviewed_diff(previous)
            if old == full:
                if previous_active:
                    print("Same changes as the previous review; skipping.")
                    return
            else:
                replayed = git("merge-tree", "--write-tree", "--merge-base", old_base, base, old_head)
                save("increment.diff", git(*DIFF_ARGS, replayed, head, raw=True))
                depth = "increment"
        except subprocess.CalledProcessError:
            print("Previous review could not be replayed; reviewing the whole PR.")
    if not active_review(context(number), expected):
        return
    resolved = gh(
        "api", "graphql", "--paginate", "-f", f"owner={REPO.split('/')[0]}", "-f", f"name={REPO.split('/')[1]}",
        "-F", f"pr={number}", "-f",
        """query=query($owner: String!, $name: String!, $pr: Int!, $endCursor: String) {
          repository(owner: $owner, name: $name) { pullRequest(number: $pr) {
            reviewThreads(first: 100, after: $endCursor) {
              pageInfo { hasNextPage endCursor }
              nodes { isResolved path line originalLine comments(first: 1) { nodes { databaseId } } }
            }
          } }
        }""",
        "--jq", '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved)',
    )
    save("resolved.jsonl", resolved)
    save("pr.diff", full)
    result = agent(f"{prompt}\nReview mode: {depth}. PR context: {CONTEXT}/{number}.json.",
                   '{"summary":"...", "open_blocking":0, "open_non_blocking":0, '
                   '"findings":[{"path":"...", "line":123, "side":"RIGHT", "body":"issue (blocking): ..."}]}')
    fields(result, "summary", "open_blocking", "open_non_blocking", "findings")
    summary = text(result["summary"], 12000)
    blocking, non_blocking = result["open_blocking"], result["open_non_blocking"]
    check(all(type(n) is int and 0 <= n <= 100 for n in (blocking, non_blocking)), "Invalid finding counts")
    findings = result["findings"]
    check(type(findings) is list and len(findings) <= 30, "Invalid findings array")
    patches = {item["filename"]: patch_lines(item.get("patch", ""))
               for item in api(f"pulls/{number}/files", paginate=True)}
    counts = {"blocking": 0, "non-blocking": 0}
    seen = set()
    comments = []
    for finding in findings:
        fields(finding, "path", "line", "side", "body")
        path, line, side = text(finding["path"], 4096), finding["line"], finding["side"]
        if finding["path"] in patches:
            path = finding["path"]
        check(type(line) is int and side in ("LEFT", "RIGHT") and (side, line) in patches.get(path, ()),
              "Finding does not refer to a commentable line of the current PR")
        check((path, line, side) not in seen, "Duplicate inline finding location")
        seen.add((path, line, side))
        body = text(finding["body"], 3000)
        match = re.match(r"(?:issue|suggestion|question|nitpick|todo|thought|note) \((blocking|non-blocking)\): \S", body)
        check(match, "Invalid Conventional Comments finding")
        counts[match[1]] += 1
        comments.append(dict(path=path, line=line, side=side, body=body))
    check(blocking >= counts["blocking"] and non_blocking >= counts["non-blocking"], "Inconsistent finding counts")
    verdict = ("OK to merge." if not non_blocking else f"OK to merge ({non_blocking} non-blocking suggestions).")
    if blocking:
        verdict = f"Issues found: {blocking} blocking, {non_blocking} non-blocking."
    with app_token() as token:
        if not active_review(api(f"pulls/{number}"), expected):
            print("PR changed; discarding review.")
            return
        own_pr = author == BOT
        event = "COMMENT" if own_pr else ("REQUEST_CHANGES" if blocking else "APPROVE")
        note = "\n\nNo approval or change request was submitted on the app's own PR." if own_pr else ""
        body = f"**Verdict: {verdict}**\n\n{summary}{note}\n\n<!-- opencode-review: {' '.join(marker)} -->"
        # GitHub persists the summary, inline comments, verdict and retry marker together.
        submitted = api(f"pulls/{number}/reviews", token=token, payload={
            "commit_id": head, "event": event, "body": body, "comments": comments,
        })
        if not own_pr:
            if not active_review(api(f"pulls/{number}"), expected):
                dismiss_review(number, submitted["id"], token, STALE_VERDICT)
            elif event == "APPROVE":
                reconcile_reviews(number, token=token)


def git_http_env(token):
    auth = base64.b64encode(f"x-access-token:{token}".encode()).decode()
    print(f"::add-mask::{auth}", flush=True)
    return dict(os.environ, GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="http.https://github.com/.extraheader",
                GIT_CONFIG_VALUE_0=f"Authorization: Basic {auth}", GIT_TERMINAL_PROMPT="0")


def main(mode):
    number = int(os.environ["NUMBER"])
    head = os.environ["HEAD"]
    retargeted = os.environ.get("RETARGETED") == "true"
    if mode == "reconcile-reviews":
        reconcile_reviews(number)
        return
    check(mode == "review", "Expected review or reconcile-reviews")
    CONTEXT.mkdir(parents=True, exist_ok=True)
    review(number, head, Path(__file__).with_name("review.md").read_text(), retargeted)


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except subprocess.CalledProcessError as error:
        # Command arguments may include credentials; don't log them.
        sys.exit(f"Command failed with exit code {error.returncode}")
    except (ValueError, KeyError) as error:
        sys.exit(str(error))
