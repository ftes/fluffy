import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import run


class CliResultTest(unittest.TestCase):
    def test_final_completed_step_is_the_only_result(self):
        events = [
            {"type": "step_start"},
            {"type": "text", "part": {"text": "I'll check."}},
            {"type": "step_finish", "part": {"reason": "tool-calls"}},
            {"type": "step_start"},
            {"type": "text", "part": {"text": '{"ok":'}},
            {"type": "text", "part": {"text": "true}"}},
            {"type": "step_finish", "part": {"reason": "stop"}},
        ]
        self.assertEqual(run.result_from_events(map(json.dumps, events)), {"ok": True})
        with self.assertRaisesRegex(ValueError, "did not finish"):
            run.result_from_events(map(json.dumps, events[:-1]))
        with self.assertRaisesRegex(ValueError, "provider.rate-limit"):
            run.result_from_events(map(json.dumps, [*events, {
                "type": "error", "error": {"type": "provider.rate-limit"},
            }]))

    def test_read_only_modes_never_allow_writes(self):
        for mode in ("triage", "review"):
            config = run.config(mode)
            self.assertEqual(config["share"], "disabled")
            self.assertEqual(config["permissions"][0], run.permission("*", effect="deny"))
            self.assertEqual({rule["action"] for rule in config["permissions"] if rule["effect"] == "allow"},
                             {"read", "glob", "grep"})

    def test_review_locations_are_line_and_side_specific(self):
        diff = "@@ -12,2 +42,3 @@\n context\n-old\n+new\n+next\n\\ No newline at end of file"
        self.assertEqual(run.patch_lines(diff), {("RIGHT", 42), ("LEFT", 13), ("RIGHT", 43), ("RIGHT", 44)})
        with self.assertRaisesRegex(ValueError, "Reserved review marker"):
            run.text("Fake\n<!-- opencode-review: ... -->", 100)


class GateTest(unittest.TestCase):
    def setUp(self):
        self.repo = patch.object(run, "REPO", "ftes/fluffy")
        self.repo.start()
        self.addCleanup(self.repo.stop)

    def gate(self, *, body="@claude please fix", association="OWNER", owner="ftes",
             branch="topic", permission="admin", event_type="issue_comment"):
        event = {
            "sender": {"login": "alice"},
            "comment": {"body": body, "author_association": association, "user": {"type": "User"}},
            "issue": {"number": 12, "pull_request": {} if owner is None else {"url": "pulls/12"}},
        }
        responses = [
            {"permission": permission},
            {"state": "open", "head": {"repo": {"full_name": f"{owner}/fluffy"}, "ref": branch}},
        ]
        with (tempfile.TemporaryDirectory() as tmp, patch.object(run, "api", side_effect=responses) as api):
            event_path = Path(tmp) / "event"
            event_path.write_text(json.dumps(event))
            out = Path(tmp) / "out"
            with patch.dict(os.environ, GITHUB_EVENT_PATH=str(event_path), GITHUB_OUTPUT=str(out),
                            GITHUB_EVENT_NAME=event_type, GITHUB_RUN_ID="99"):
                run.gate()
            return out.read_text() if out.exists() else "", api.call_count

    def test_legacy_mention_and_trusted_command(self):
        self.assertIn("branch=topic\n", self.gate()[0])
        self.assertIn("branch=opencode/issue-12-99\n", self.gate(body="/oc fix it", owner=None)[0])

    def test_untrusted_comment_and_read_only_collaborator(self):
        self.assertEqual(self.gate(association="NONE"), ("", 0))
        self.assertEqual(self.gate(association="COLLABORATOR", permission="read"), ("", 1))
        self.assertEqual(self.gate(body="/octopus"), ("", 0))

    def test_fork_notice_and_renovate_skip(self):
        self.assertEqual(self.gate(owner="fork")[0], "fork=true\nnumber=12\n")
        self.assertEqual(self.gate(owner="fork", event_type="pull_request_review_comment")[0], "")
        self.assertEqual(self.gate(branch="renovate/dependency")[0], "")


class PublishTest(unittest.TestCase):
    def test_triage_rejects_out_of_scope_pr_before_any_write(self):
        decisions = [{"number": 42, "action": "close", "why": "Obsolete"},
                     {"number": 123, "action": "close", "why": "Different PR"}]
        with (patch.dict(os.environ, NUMBERS="42 56"),
              patch.object(run, "context"), patch.object(run, "pr_diff"),
              patch.object(run, "agent", return_value={"decisions": decisions}),
              patch.object(run, "app_token") as token):
            with self.assertRaisesRegex(ValueError, "Invalid triage PR"):
                run.triage("Triage")
        token.assert_not_called()

    def test_approval_is_bound_to_the_reviewed_commit_and_marker_follows(self):
        head = "a" * 40
        fork = "b" * 40
        pr = {"head": {"sha": head, "ref": "topic", "repo": {"full_name": "ftes/fluffy"}},
              "base": {"ref": "main"}, "draft": False, "state": "open",
              "user": {"login": "alice", "type": "User"}}
        responses = [pr, [], [], pr, {}, pr, {}]
        with (patch.object(run, "REPO", "ftes/fluffy"),
              patch.object(run, "api", side_effect=responses) as api,
              patch.object(run, "app_token", return_value=contextlib.nullcontext("app-token")),
              patch.object(run, "agent", return_value={
                  "summary": "Checked calls", "open_blocking": 0, "open_non_blocking": 0, "findings": [],
              }),
              patch.object(run, "git", side_effect=[fork, "diff"]),
              patch.object(run, "gh"), patch.object(run, "save"), patch.object(run, "context"),
              contextlib.redirect_stdout(io.StringIO())):
            run.review(42, head, "Review")
        writes = [(call.args[0], call.kwargs["payload"]) for call in api.call_args_list if "payload" in call.kwargs]
        self.assertEqual([path for path, _ in writes], ["pulls/42/reviews", "issues/42/comments"])
        self.assertEqual(writes[0][1]["event"], "APPROVE")
        self.assertEqual(writes[0][1]["commit_id"], head)
        self.assertTrue(writes[1][1]["body"].endswith(f"<!-- opencode-review: {head} {fork} -->"))
