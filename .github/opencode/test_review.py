import contextlib
import json
import os
from pathlib import Path
import random
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import review
import run


class ReviewWorkflowTest(unittest.TestCase):
    def test_request_uses_the_associated_same_repo_pull_request_and_run_head(self):
        event = {"repository": {"id": 1}, "workflow_run": {
            "display_title": "Review 42 edited", "event": "pull_request", "conclusion": "success",
            "path": ".github/workflows/opencode-review.yml", "head_repository": {"full_name": "ftes/fluffy"},
            "head_sha": "a" * 40, "pull_requests": [{"number": 42, "head": {"repo": {"id": 1}}}],
        }}
        with patch.object(run, "REPO", "ftes/fluffy"):
            self.assertEqual(review.request(event), (42, "a" * 40, True))
            source = event["workflow_run"]
            for update in (
                {"display_title": "Skip automatic review"}, {"display_title": "Review 43 opened"},
                {"event": "workflow_dispatch"}, {"path": ".github/workflows/schedule.yml"},
                {"head_repository": {"full_name": "fork/fluffy"}},
                {"pull_requests": [{"number": 42, "head": {"repo": {"id": 2}}}]},
            ):
                self.assertIsNone(review.request(event | {"workflow_run": source | update}))

    def test_source_export_uses_git_objects_and_excludes_symlinks(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.chdir(directory):
            run.git("init", "-q")
            commit = ("-c", "user.name=Test", "-c", "user.email=test@example.com",
                      "-c", "commit.gpgsign=false", "commit", "-qm")
            run.git(*commit, "base", "--allow-empty")
            base = run.git("rev-parse", "HEAD")
            Path("source.ex").write_text("from head\n")
            Path("link").symlink_to("/etc/passwd")
            run.git("add", "source.ex", "link")
            run.git(*commit, "change")
            Path("source.ex").write_text("from working tree\n")
            self.assertEqual(review.changed_sources(base, "HEAD", 1024), {"source.ex": "from head\n"})

    def test_full_and_incremental_context_keep_binary_notices_and_text_hunks(self):
        with tempfile.TemporaryDirectory() as tmp, contextlib.chdir(tmp):
            directory = Path(tmp)
            run.git("init", "-q")
            commit = ("-c", "user.name=Test", "-c", "user.email=test@example.com",
                      "-c", "commit.gpgsign=false", "commit", "-qm")
            run.git(*commit, "base", "--allow-empty")
            base = run.git("rev-parse", "HEAD")
            Path("source.ex").write_text("before\n")
            Path("fixture.bin").write_bytes(b"\0before")
            run.git("add", "source.ex", "fixture.bin")
            run.git(*commit, "prior review")
            previous = run.git("rev-parse", "HEAD")
            Path("source.ex").write_text("after\n")
            Path("fixture.bin").write_bytes(b"\0" + random.Random(42).randbytes(review.MAX_CONTEXT))
            run.git("add", "source.ex", "fixture.bin")
            run.git(*commit, "new head")
            head = run.git("rev-parse", "HEAD")
            pr = {"number": 42, "head": {"sha": head, "ref": "feature", "repo": {"full_name": "ftes/fluffy"}},
                  "base": {"sha": base, "ref": "main"}, "draft": False, "state": "open",
                  "user": {"login": "alice", "type": "User"}}
            marker = run.snapshot_marker((previous, "main", base), base)

            def context(number):
                run.save(f"{number}.json", pr)
                return pr

            with (patch.object(run, "REPO", "ftes/fluffy"),
                  patch.object(run, "CONTEXT", directory),
                  patch.object(run, "api", return_value=pr),
                  patch.object(run, "previous_review", return_value=(marker, True)),
                  patch.object(run, "context", side_effect=context),
                  patch.object(run, "gh", return_value="")):
                self.assertGreater(len(run.snapshot_diff(pr)[1]), review.MAX_CONTEXT)
                self.assertIn(b"GIT binary patch", run.reviewed_diff(marker))
                self.assertTrue(review.prepare(42, head, False, directory))
                data = json.loads((directory / "review-input.json").read_text())["data"]
                self.assertEqual(data["mode"], "increment")
                for diff in (data["diff"], data["increment"]):
                    self.assertIn("Binary files ", diff)
                    self.assertIn("+after", diff)
                    self.assertNotIn("GIT binary patch", diff)
                (directory / "review-input.json").unlink()
                with patch.object(review, "MAX_CONTEXT", 100):
                    with self.assertRaisesRegex(ValueError, "review this PR manually"):
                        review.prepare(42, head, False, directory)
                self.assertFalse((directory / "review-input.json").exists())

    def test_inference_uses_only_claude_oauth_in_an_empty_working_directory(self):
        result = {"summary": "first\u2028second"}
        events = [
            {"type": "step_start"},
            {"type": "text", "part": {"text": json.dumps(result, ensure_ascii=False)}},
            {"type": "step_finish", "part": {"reason": "stop"}},
        ]

        def cli(args, **kwargs):
            self.assertEqual(list(kwargs["cwd"].iterdir()), [])
            return subprocess.CompletedProcess(
                args, 0, stdout="".join(json.dumps(event, ensure_ascii=False) + "\n" for event in events),
            )

        with (patch.dict(os.environ, CLAUDE_CODE_OAUTH_TOKEN="test", GH_TOKEN="hidden",
                         ACTIONS_ID_TOKEN_REQUEST_TOKEN="hidden", OPENCODE_API_KEY="hidden"),
              patch.object(subprocess, "run", side_effect=cli) as command):
            self.assertEqual(review.infer({"diff": "reference"}), result)
        login, request = command.call_args_list
        self.assertEqual(login.args[0], ["opencode", "--standalone", "auth", "login", "claude-agent",
                                         "--method", "claude-login"])
        self.assertEqual(request.args[0][-2:], ["--model", review.MODEL])
        env = request.kwargs["env"]
        self.assertFalse(env.keys() & {"GH_TOKEN", "ACTIONS_ID_TOKEN_REQUEST_TOKEN", "OPENCODE_API_KEY"})
        self.assertEqual(env["CLAUDE_CODE_OAUTH_TOKEN"], "test")
        self.assertIn('"diff": "reference"', request.kwargs["input"])
        settings = json.loads(env["OPENCODE_CONFIG_CONTENT"])
        self.assertEqual(settings["providers"]["claude-agent"]["models"]["ci-sonnet"]["modelID"], "sonnet")
        self.assertEqual(settings["permissions"], [run.permission("*", effect="deny")])
        self.assertIn(run.permission("tool.use", effect="deny"), settings["policies"])
