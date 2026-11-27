import contextlib
import json
import os
from pathlib import Path
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

    def test_inference_uses_only_claude_oauth_in_an_empty_working_directory(self):
        events = [
            {"type": "step_start"},
            {"type": "text", "part": {"text": '{}'}},
            {"type": "step_finish", "part": {"reason": "stop"}},
        ]

        def cli(args, **kwargs):
            self.assertEqual(list(kwargs["cwd"].iterdir()), [])
            return subprocess.CompletedProcess(args, 0, stdout="\n".join(map(json.dumps, events)))

        with (patch.dict(os.environ, CLAUDE_CODE_OAUTH_TOKEN="test", GH_TOKEN="hidden",
                         ACTIONS_ID_TOKEN_REQUEST_TOKEN="hidden", OPENCODE_API_KEY="hidden"),
              patch.object(subprocess, "run", side_effect=cli) as command):
            self.assertEqual(review.infer({"diff": "reference"}), {})
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
