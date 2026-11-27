import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import command
import run


REPO = "ftes/fluffy"
HEAD = "a" * 40
BRANCH = "feature"
MEMBER = {"login": "alice", "type": "User"}


def pr(branch=BRANCH, repo=REPO, head=HEAD, state="open"):
    return {"state": state, "head": {"sha": head, "ref": branch, "repo": {"full_name": repo}}}


def request(body="/agent fix the test", association="OWNER", author=MEMBER):
    return {"body": body, "author_association": association, "user": author}


class GateTest(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(run, "REPO", REPO))

    def test_agent_command_on_all_existing_events(self):
        issue = {"number": 32}
        pull_request = {"number": 32}
        events = (
            ("issue_comment", {"comment": request("/agent fix"), "issue": issue}, False),
            ("issues", {"issue": issue | request(None) | {"title": "/agent fix"}}, False),
            ("pull_request_review_comment", {"comment": request("/agent fix"), "pull_request": pull_request}, True),
            ("pull_request_review", {"review": request("/agent fix"), "pull_request": pull_request}, True),
            ("issue_comment", {"comment": request(), "issue": issue | {"pull_request": {"url": "pulls/32"}}}, True),
        )
        for event_name, data, is_pr in events:
            with self.subTest(event=event_name, is_pr=is_pr), patch.object(
                run, "api", side_effect=[{"permission": "write"}, pr()]
            ):
                result = command.target(data | {"sender": MEMBER}, event_name, "main", "99")
                self.assertEqual(result["branch"], BRANCH if is_pr else "opencode/issue-32-99")
                self.assertEqual(result.get("pr"), "true" if is_pr else None)
                self.assertEqual(result.get("head"), HEAD if is_pr else None)

    def test_deny_outsiders_and_bots(self):
        for denied in (request(association="NONE"), request(author=MEMBER | {"type": "Bot"})):
            event = {"sender": MEMBER, "comment": denied, "issue": {"number": 32}}
            with patch.object(run, "api") as api:
                self.assertEqual(command.target(event, "issue_comment", "main", "99"), {})
            api.assert_not_called()

    def test_reject_legacy_and_inexact_commands(self):
        for body in ("@claude fix", "@opencode fix", "/oc fix", "/opencode fix",
                     "/agentic", "/agent-help", "docs/agent", "/agent/status"):
            with self.subTest(body=body), patch.object(run, "api") as api:
                event = {"sender": MEMBER, "comment": request(body), "issue": {"number": 32}}
                self.assertEqual(command.target(event, "issue_comment", "main", "99"), {})
                api.assert_not_called()

    def test_assigned_issue_requires_write_access_for_the_sender_and_author(self):
        event = {"sender": MEMBER, "issue": {"number": 32} | request(author=MEMBER | {"login": "bob"})}
        with patch.object(run, "api", side_effect=[{"permission": "write"}, {"permission": "read"}]) as api:
            self.assertEqual(command.target(event, "issues", "main", "99"), {})
        self.assertEqual([call.args[0] for call in api.call_args_list],
                         ["collaborators/alice/permission", "collaborators/bob/permission"])

    def test_fork_notice_and_protected_targets(self):
        event = {"sender": MEMBER, "comment": request(), "issue": {"number": 32, "pull_request": {"url": "pulls/32"}}}
        cases = (pr(repo="fork/fluffy"), pr(branch="renovate/update"), pr(branch="main"), pr(state="closed"),
                 pr(branch=f"{run.PLAYWRIGHT_PILOT_BRANCH}1.65.0"))
        for candidate in cases:
            with patch.object(run, "api", side_effect=[{"permission": "admin"}, candidate]):
                expected = {"fork": "true", "number": 32} if candidate["head"]["repo"]["full_name"] != REPO else {}
                self.assertEqual(command.target(event, "issue_comment", "main", "99"), expected)
        inline = {"sender": MEMBER, "comment": request(), "pull_request": {"number": 32}}
        with patch.object(run, "api", side_effect=[{"permission": "admin"}, cases[0]]):
            self.assertEqual(command.target(inline, "pull_request_review_comment", "main", "99"), {})

    def test_gate_only_passes_the_exact_approved_head_and_trusted_commit(self):
        event = {"sender": MEMBER, "comment": request(),
                 "issue": {"number": 32, "pull_request": {"url": "pulls/32"}}}
        base = "b" * 40
        with tempfile.TemporaryDirectory() as directory:
            event_path = Path(directory) / "event.json"
            event_path.write_text(json.dumps(event))
            output = Path(directory) / "output"
            with patch.dict(os.environ, GITHUB_EVENT_PATH=str(event_path), GITHUB_OUTPUT=str(output),
                            GITHUB_EVENT_NAME="issue_comment", DEFAULT_BRANCH="main", GITHUB_RUN_ID="99"):
                for allowed in (False, True):
                    with (patch.object(run, "api", side_effect=[{"permission": "admin"}, pr()]),
                          patch.object(run, "git", return_value=base),
                          patch.object(run, "privileged_setup_allowed", return_value=allowed) as guard,
                          contextlib.redirect_stdout(io.StringIO())):
                        command.main("gate")
                    guard.assert_called_once_with(base, HEAD, BRANCH)
                    actual = dict(line.split("=", 1) for line in output.read_text().splitlines())
                    self.assertEqual(actual, {"run": "true", "pr": "true", "number": "32", "branch": BRANCH,
                                              "head": HEAD, "trusted": base} if allowed else {})


class PublishTest(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(run, "REPO", REPO))

    def test_edit_mode_does_not_enable_shell_or_change_review_mode(self):
        allowed = {rule["action"] for rule in command.settings()["permissions"] if rule["effect"] == "allow"}
        self.assertEqual(allowed, {"edit", "glob", "grep", "read"})
        self.assertEqual(run.config()["share"], "disabled")
        self.assertNotIn("edit", {rule["action"] for rule in run.config()["permissions"]})

    def test_git_stage_rejects_renaming_a_workflow_out_of_protected_paths(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.chdir(directory):
            run.git("init", "-q")
            workflow = Path(".github/workflows/example.yml")
            workflow.parent.mkdir(parents=True)
            workflow.write_text("name: example\n")
            run.git("add", "-A")
            run.git("-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false",
                    "commit", "-qm", "base")
            workflow.rename("example.yml")
            with self.assertRaisesRegex(ValueError, "cannot publish"):
                command.stage(run.git("rev-parse", "HEAD"))

    def test_pr_change_does_not_push_or_reply_if_head_moves(self):
        replies = [pr(), [], pr(head="b" * 40)]
        with (patch.object(run, "api", side_effect=replies) as api,
              patch.object(run, "git", side_effect=[HEAD, ""]),
              patch.object(run, "context"), patch.object(run, "save"), patch.object(run, "gh"),
              patch.object(run, "snapshot_diff", return_value=("base", b"diff")),
              patch.object(run, "agent", return_value={"title": "Fix the test", "reply": "Updated."}),
              patch.object(command, "recover", return_value=None),
              patch.object(command, "commit", return_value="c" * 40),
              patch.object(command, "stage", return_value=True),
              patch.object(command, "push") as push,
              patch.object(run, "app_token", return_value=contextlib.nullcontext("token"))):
            command.command(32, BRANCH, "main", True, "99", "Prompt", request())
        push.assert_not_called()
        self.assertTrue(all("payload" not in call.kwargs for call in api.call_args_list))

    def test_pr_change_uses_the_inspected_head_as_the_push_lease(self):
        with (patch.object(run, "api", side_effect=[pr(), [], pr(), {}]) as api,
              patch.object(run, "git", side_effect=[HEAD, ""]),
              patch.object(run, "context"), patch.object(run, "save"), patch.object(run, "gh"),
              patch.object(run, "snapshot_diff", return_value=("base", b"diff")),
              patch.object(run, "agent", return_value={"title": "Fix the test", "reply": "Updated."}),
              patch.object(command, "recover", return_value=None),
              patch.object(command, "commit", return_value="c" * 40),
              patch.object(command, "stage", return_value=True),
              patch.object(command, "push") as push,
              patch.object(run, "app_token", return_value=contextlib.nullcontext("token"))):
            command.command(32, BRANCH, "main", True, "99", "Prompt", request())
        push.assert_called_once_with(BRANCH, "token", HEAD)
        self.assertEqual(api.call_args.kwargs["payload"]["body"], "Updated.\n\n<!-- opencode-command: 99 -->")

    def test_issue_publication_recovers_without_repeating_model_or_push(self):
        branch = "opencode/issue-32-99"
        with (patch.object(run, "api", side_effect=[[], {}]) as api, patch.object(run, "git", return_value=HEAD),
              patch.object(run, "agent") as agent, patch.object(command, "push") as push,
              patch.object(command, "recover", return_value=(HEAD, "Fix the test", "Updated.")),
              patch.object(command, "issue_pr", return_value="https://example.test/pull/33") as publish,
              patch.object(run, "app_token", return_value=contextlib.nullcontext("token"))):
            command.command(32, branch, "main", False, "99", "Prompt", request())
        agent.assert_not_called()
        push.assert_not_called()
        publish.assert_called_once()
        self.assertIn("Opened https://example.test/pull/33", api.call_args.kwargs["payload"]["body"])
