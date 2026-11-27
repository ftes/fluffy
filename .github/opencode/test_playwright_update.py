import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import playwright_update as updater
import publish
import run


RELEASE = "1.65.0"
BRANCH = f"opencode/playwright-ex-{RELEASE}"
HEAD = "a" * 40
OLD = "b" * 40
BASE = "c" * 40
REPO = "ftes/fluffy"


def pr(state, sha, *, merged=False):
    return {"state": state, "merged_at": "2026-11-26T00:00:00Z" if merged else None,
            "head": {"sha": sha, "ref": BRANCH, "repo": {"full_name": REPO}},
            "base": {"ref": "main"}, "user": {"login": run.BOT},
            "html_url": "https://example.test/pull/42"}


def updated_files():
    lock = f'  "playwright": {{:hex, :playwright_ex, "{RELEASE}", ...}}\n'
    return dict.fromkeys(updater.LOCKFILES, lock) | {
        "mix.exs": f'{{:playwright, "~> {RELEASE}", hex: :playwright_ex}}',
        "CHANGELOG.md": f"## Unreleased\n\n- Requires PlaywrightEx {RELEASE}.\n",
    }


class PlaywrightUpdateTest(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(run, "REPO", REPO))

    def test_closed_history_and_retained_branches_follow_retry_policy(self):
        closed = pr("closed", OLD)
        for event, previous, current, legacy_head, head, expected in [
            ("schedule", [], [closed], None, None, "skip"),
            ("schedule", [closed], [], None, None, "skip"),
            ("workflow_dispatch", [], [closed], None, OLD, "skip"),
            ("workflow_dispatch", [closed], [], OLD, None, "skip"),
            ("workflow_dispatch", [], [closed], None, None, "new"),
            ("workflow_dispatch", [closed], [], None, None, "new"),
            ("workflow_dispatch", [], [closed], None, HEAD, "recover"),
            ("schedule", [], [closed], None, HEAD, "recover"),
            ("schedule", [], [], None, HEAD, "recover"),
            ("workflow_dispatch", [], [], None, HEAD, "recover"),
            ("workflow_dispatch", [], [pr("open", OLD)], None, HEAD, "skip"),
            ("workflow_dispatch", [], [pr("closed", OLD, merged=True)], None, None, "skip"),
        ]:
            with self.subTest(event=event, previous=previous, current=current, head=head):
                self.assertEqual(updater.plan(event, previous, current, legacy_head, head)[0], expected)

    def test_open_draft_ignores_old_closed_pr_but_rejects_other_open_pr(self):
        historical = pr("closed", OLD)
        opened = pr("open", HEAD)
        with (patch.object(publish, "pull_requests", return_value=[historical]),
              patch.object(publish, "remote_head", return_value=HEAD),
              patch.object(run, "api", return_value=opened) as api):
            result = updater.open_draft(BRANCH, "main", RELEASE, HEAD, "Updated docs.", "app")
        self.assertEqual(result, (opened["html_url"], "open"))
        self.assertTrue(api.call_args.kwargs["payload"]["draft"])
        self.assertEqual(api.call_args.kwargs["token"], "app")

        with (patch.object(publish, "pull_requests", return_value=[pr("open", OLD)]),
              patch.object(run, "api") as api):
            with self.assertRaisesRegex(ValueError, "Existing PR"):
                updater.open_draft(BRANCH, "main", RELEASE, HEAD, "Updated docs.", "app")
        api.assert_not_called()

    def test_existing_publication_returns_its_url_and_state_without_recreating_it(self):
        for state in ("open", "closed"):
            existing = pr(state, HEAD)
            with (patch.object(publish, "pull_requests", return_value=[pr("closed", OLD), existing]),
                  patch.object(run, "api") as api):
                self.assertEqual(updater.open_draft(BRANCH, "main", RELEASE, HEAD, "Updated docs.", "app"),
                                 (existing["html_url"], state))
            api.assert_not_called()

    def test_fresh_run_recovers_pushed_update_without_model_or_push(self):
        body = "Updated docs." + updater.CHECKS
        record = {"message": f"Update PlaywrightEx to {RELEASE}\n\n{body}\n\nOpenCode-PlaywrightEx-Isolated: {RELEASE} 9 10",
                  "author": {"email": publish.BOT_EMAIL}, "parents": [{"sha": OLD}]}
        workflow = {"path": ".github/workflows/playwright-ex-update.yml", "head_sha": OLD, "event": "schedule"}
        files = updated_files()
        with (patch.object(publish, "remote_head", side_effect=[HEAD, BASE]),
              patch.object(run, "api", side_effect=[record, workflow]),
              patch.object(run, "git", return_value=BASE) as git,
              patch.object(run, "ensure_commit"),
              patch.object(updater, "read_artifact", return_value={"files": files, "body": "Updated docs."}) as load,
              patch.object(updater, "changed_files", return_value=files),
              patch.object(run, "agent") as model, patch.object(publish, "push") as push,
              patch.object(run, "app_token", return_value=contextlib.nullcontext("app")),
              patch.object(updater, "open_draft", return_value=("https://example.test/pull/42", "open")) as open_pr,
              patch("builtins.print")):
            updater.publish_update("recover", RELEASE, "main", BASE, "11", "", HEAD)
        git.assert_any_call("merge-base", "--is-ancestor", OLD, BASE)
        load.assert_called_once_with("10", "verified", "9", OLD, RELEASE)
        open_pr.assert_called_once_with(BRANCH, "main", RELEASE, HEAD, body, "app")
        model.assert_not_called()
        push.assert_not_called()

    def test_a_branch_without_the_release_publication_marker_cannot_recover(self):
        record = {"message": "Not an update", "author": {"email": publish.BOT_EMAIL}, "parents": [{"sha": OLD}]}
        with (patch.object(publish, "remote_head", return_value=HEAD), patch.object(run, "api", return_value=record),
              patch.object(run, "ensure_commit") as fetch):
            with self.assertRaisesRegex(ValueError, "not a recoverable"):
                updater.recover(BRANCH, RELEASE, BASE, HEAD)
        fetch.assert_not_called()

    def test_lockfiles_and_dependency_floor_all_match(self):
        files = updated_files()
        updater.validate_version(RELEASE, files)
        for file in (*updater.LOCKFILES, "mix.exs"):
            with self.assertRaisesRegex(ValueError, file):
                updater.validate_version(RELEASE, files | {file: files[file].replace(RELEASE, f"{RELEASE}-rc.6")})

    def test_artifact_must_match_the_run_base_and_exact_file(self):
        data = updater.identity("verified", "9", BASE, RELEASE) | {"files": updated_files(), "body": "Updated."}
        record = {"expired": False, "size_in_bytes": 2048, "name": "playwright-verified-1",
                  "workflow_run": {"id": 9, "head_sha": BASE, "repository_id": 1, "head_repository_id": 1}}

        def archive(payload, extra=None):
            output = io.BytesIO()
            with zipfile.ZipFile(output, "w") as contents:
                contents.writestr("verified.json", json.dumps(payload))
                if extra:
                    contents.writestr(extra, "unexpected")
            return output.getvalue()

        with patch.object(run, "api", return_value=record):
            with patch.object(run, "gh", return_value=archive(data)):
                self.assertEqual(updater.read_artifact("10", "verified", "9", BASE, RELEASE), data)
                with self.assertRaisesRegex(ValueError, "selected update run and base"):
                    updater.read_artifact("10", "verified", "9", OLD, RELEASE)
            with patch.object(run, "gh", return_value=archive(data | {"release": "1.2.3"})):
                with self.assertRaisesRegex(ValueError, "metadata does not match"):
                    updater.read_artifact("10", "verified", "9", BASE, RELEASE)
            with patch.object(run, "gh", return_value=archive(data, ".git/config")):
                with self.assertRaisesRegex(ValueError, "Unexpected artifact files"):
                    updater.read_artifact("10", "verified", "9", BASE, RELEASE)

    def test_cannot_publish_runner_scripts_executables_or_new_paths(self):
        for path in (".git/config", ".github/opencode/playwright_update.py", "lib/other.ex"):
            with self.assertRaisesRegex(ValueError, "Unexpected update paths"):
                updater.checked_files({"files": updated_files() | {path: "new"}, "body": "Updated."}, RELEASE)

    def test_apply_only_regular_inventory_and_stage_without_touching_worktree(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.chdir(directory):
            run.git("init", "-q")
            inventory = Path(updater.INVENTORY)
            inventory.parent.mkdir(parents=True)
            inventory.write_text("old\n")
            Path("other.txt").write_text("old\n")
            run.git("add", "-A")
            run.git("-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false",
                    "commit", "-qm", "base")
            parent = run.git("rev-parse", "HEAD")
            patch_text = f"--- a/{updater.INVENTORY}\n+++ b/{updater.INVENTORY}\n@@ -1 +1 @@\n-old\n+new\n"
            updater.stage_replacements(parent, {updater.INVENTORY: "new\n"})
            self.assertEqual(inventory.read_text(), "old\n")
            self.assertEqual(run.git("show", f":{updater.INVENTORY}"), "new")
            run.git("read-tree", parent)
            updater.apply_inventory(patch_text)
            self.assertEqual(inventory.read_text(), "new\n")
            run.git("read-tree", parent)
            with self.assertRaisesRegex(ValueError, "only modify"):
                updater.apply_inventory(patch_text.replace(updater.INVENTORY, "other.txt"))
            self.assertEqual(Path("other.txt").read_text(), "old\n")
