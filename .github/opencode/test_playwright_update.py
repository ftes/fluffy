import contextlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

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
        record = {"message": f"Update PlaywrightEx to {RELEASE}\n\nUpdated docs.\n\nOpenCode-PlaywrightEx: {RELEASE}\n",
                  "author": {"email": publish.BOT_EMAIL}, "parents": [{"sha": OLD}]}
        with (patch.object(publish, "remote_head", return_value=HEAD),
              patch.object(run, "api", return_value=record),
              patch.object(run, "git", return_value=BASE) as git,
              patch.object(run, "ensure_commit"), patch.object(updater, "validate_version") as validate,
              patch.object(run, "agent") as model, patch.object(publish, "push") as push,
              patch.object(run, "app_token", return_value=contextlib.nullcontext("app")),
              patch.object(updater, "open_draft", return_value=("https://example.test/pull/42", "open")) as open_pr,
              patch("builtins.print")):
            updater.update("recover", "1.64.0", RELEASE, "main", BASE)
        git.assert_any_call("merge-base", "--is-ancestor", OLD, BASE)
        validate.assert_called_once_with(RELEASE, HEAD)
        open_pr.assert_called_once_with(BRANCH, "main", RELEASE, HEAD, "Updated docs.", "app")
        model.assert_not_called()
        push.assert_not_called()

    def test_a_branch_without_the_release_publication_marker_cannot_recover(self):
        record = {"message": "Not an update", "author": {"email": publish.BOT_EMAIL}, "parents": [{"sha": OLD}]}
        with (patch.object(publish, "remote_head", return_value=HEAD), patch.object(run, "api", return_value=record),
              patch.object(run, "ensure_commit") as fetch):
            with self.assertRaisesRegex(ValueError, "not a recoverable"):
                updater.recover(BRANCH, RELEASE, BASE)
        fetch.assert_not_called()

    def test_lockfiles_and_dependency_floor_all_match(self):
        lock = f'  "playwright": {{:hex, :playwright_ex, "{RELEASE}", ...}}\n'
        with tempfile.TemporaryDirectory() as directory, contextlib.chdir(directory):
            Path("integration/consumer").mkdir(parents=True)
            for file in updater.LOCKFILES:
                Path(file).write_text(lock)
            Path("mix.exs").write_text(f'{{:playwright, "~> {RELEASE}", hex: :playwright_ex}}')
            updater.validate_version(RELEASE)
            for file in updater.LOCKFILES:
                Path(file).write_text(lock.replace(RELEASE, f"{RELEASE}-rc.6"))
                with self.assertRaisesRegex(ValueError, file):
                    updater.validate_version(RELEASE)
                Path(file).write_text(lock)
            Path("mix.exs").write_text('{:playwright, "~> 1.64.0", hex: :playwright_ex}')
            with self.assertRaisesRegex(ValueError, "mix.exs"):
                updater.validate_version(RELEASE)
