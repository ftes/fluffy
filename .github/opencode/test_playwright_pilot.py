import contextlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import playwright_pilot as pilot
import playwright_update as update
import publish
import run


PREVIOUS = "1.65.0-rc.6"
RELEASE = "1.65.0"
BASE = "a" * 40
BRANCH = f"{pilot.BRANCH_PREFIX}{RELEASE}"


class PlaywrightPilotTest(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(run, "REPO", "ftes/fluffy"))

    def test_already_locked_and_older_targets_skip_before_api_access(self):
        with (tempfile.TemporaryDirectory() as directory, contextlib.chdir(directory),
              patch.object(publish, "remote_head") as lookup, patch("builtins.print")):
            Path("mix.lock").write_text(f'  "playwright": {{:hex, :playwright_ex, "{PREVIOUS}", ...}}\n')
            self.assertIsNone(pilot.select_release(PREVIOUS, "main", BASE))
            with self.assertRaisesRegex(ValueError, "older than"):
                pilot.select_release("1.65.0-rc.5", "main", BASE)
        lookup.assert_not_called()

    def test_dispatch_role_and_rerun_actor_must_match(self):
        with (patch.dict(os.environ, GITHUB_ACTOR="owner", GITHUB_TRIGGERING_ACTOR="other"),
              patch.object(run, "api") as api):
            with self.assertRaisesRegex(ValueError, "original maintainer"):
                pilot.check_actor()
            api.assert_not_called()
            os.environ["GITHUB_TRIGGERING_ACTOR"] = "owner"
            for role in ("admin", "maintain"):
                api.return_value = {"role_name": role}
                pilot.check_actor()
            api.return_value = {"role_name": "write"}
            with self.assertRaisesRegex(ValueError, "maintain or admin"):
                pilot.check_actor()

    def test_release_with_a_pilot_pr_is_a_noop_even_after_closure(self):
        pr = {"state": "closed", "merged_at": None, "base": {"ref": "main"},
              "head": {"ref": BRANCH, "repo": {"full_name": run.REPO}}}
        with (patch.object(publish, "pull_requests", return_value=[pr]),
              patch.object(publish, "remote_head") as lookup,
              patch.object(run, "app_token") as app, patch("builtins.print")):
            pilot.publish_update(RELEASE, "main", BASE, "9", "10")
        lookup.assert_not_called()
        app.assert_not_called()

    def test_occupied_branch_fails_before_loading_artifact_or_minting_app_token(self):
        with (patch.object(publish, "pull_requests", return_value=[]),
              patch.object(publish, "remote_head", return_value="b" * 40),
              patch.object(update, "read_artifact") as load, patch.object(run, "app_token") as app):
            with self.assertRaisesRegex(ValueError, "branch already exists"):
                pilot.publish_update(RELEASE, "main", BASE, "9", "10")
        load.assert_not_called()
        app.assert_not_called()

    def test_publish_uses_the_verified_id_and_a_create_only_lease(self):
        files = {name: f'  "playwright": {{:hex, :playwright_ex, "{RELEASE}", ...}}\n' for name in update.LOCKFILES}
        files |= {"mix.exs": f'{{:playwright, "~> {RELEASE}", hex: :playwright_ex}}', "CHANGELOG.md": "Updated.\n"}
        with (patch.object(publish, "pull_requests", return_value=[]),
              patch.object(publish, "remote_head", side_effect=[None, BASE, BASE, BASE]),
              patch.object(update, "read_artifact", return_value={"files": files, "body": pilot.BODY}) as load,
              patch.object(update, "stage_replacements") as stage,
              patch.object(publish, "commit", return_value="b" * 40),
              patch.object(run, "app_token", return_value=contextlib.nullcontext("app")),
              patch.object(publish, "push") as push,
              patch.object(update, "open_draft", return_value=("https://example.test/pr", "open")) as draft,
              patch("builtins.print")):
            pilot.publish_update(RELEASE, "main", BASE, "9", "10")
        load.assert_called_once_with("10", "verified", "9", BASE, RELEASE)
        stage.assert_called_once_with(BASE, files)
        push.assert_called_once_with(BRANCH, "app", "")
        draft.assert_called_once_with(BRANCH, "main", RELEASE, "b" * 40, pilot.BODY + update.CHECKS, "app")

    def test_model_uses_private_profile_and_only_the_oauth_credential(self):
        events = [
            {"type": "step_start"},
            {"type": "text", "part": {"text": '{}'}},
            {"type": "step_finish", "part": {"reason": "stop"}},
        ]
        result = subprocess.CompletedProcess([], 0, stdout="\n".join(map(json.dumps, events)))
        with (patch.dict(os.environ, CLAUDE_CODE_OAUTH_TOKEN="test", GH_TOKEN="unavailable",
                         OPENCODE_API_KEY="unavailable", ANTHROPIC_API_KEY="unavailable", PWD="/checkout"),
              patch.object(subprocess, "run", return_value=result) as cli):
            self.assertEqual(pilot.classify({"inventory": "reference"}), {})
        auth, request = cli.call_args_list
        self.assertEqual(auth.args[0], ["opencode", "--standalone", "auth", "login", "claude-agent", "--method",
                                        "claude-login"])
        self.assertEqual(auth.kwargs["stdin"], subprocess.DEVNULL)
        env = request.kwargs["env"]
        self.assertFalse(env.keys() & {"GH_TOKEN", "OPENCODE_API_KEY", "ANTHROPIC_API_KEY", "PWD"})
        self.assertEqual(env["CLAUDE_CODE_OAUTH_TOKEN"], "test")
        self.assertEqual(Path(env["HOME"]).parent, request.kwargs["cwd"].parent)
        self.assertEqual(request.args[0][-2:], ["--model", pilot.MODEL])
        self.assertIn('"inventory": "reference"', request.kwargs["input"])
        config = json.loads(env["OPENCODE_CONFIG_CONTENT"])
        self.assertEqual(config["providers"]["claude-agent"]["models"]["ci-sonnet"]["modelID"], "sonnet")
        self.assertEqual(config["permissions"], [run.permission("*", effect="deny")])
        self.assertIn(run.permission("tool.use", effect="deny"), config["policies"])

    def test_classifications_are_typed_data_and_cannot_replace_inventory_code(self):
        proposal = {"members": {"Playwright.Page": {"old_member": None, "new_member": ["unwrap", "gap"]}}}
        self.assertEqual(json.loads(pilot.update_classifications("{}", proposal)), proposal)
        for invalid in ({"patch": "arbitrary source"},
                        {"members": {"System": {"cmd": ["wrapped"]}}},
                        {"members": {"Playwright.Page": {"title": ["renamed", "System"]}}}):
            with self.assertRaises(ValueError):
                pilot.validate_classifications(invalid)
        files = {name: f'  "playwright": {{:hex, :playwright_ex, "{RELEASE}", ...}}\n' for name in update.LOCKFILES}
        files |= {"mix.exs": f'{{:playwright, "~> {RELEASE}", hex: :playwright_ex}}', "CHANGELOG.md": "Updated.\n"}
        with self.assertRaisesRegex(ValueError, "Unexpected update paths"):
            pilot.checked_files({"files": files | {update.INVENTORY: "arbitrary source"}, "body": pilot.BODY}, RELEASE)
