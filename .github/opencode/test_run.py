import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import call, patch

import run


class PrivilegedSetupTest(unittest.TestCase):
    def test_guard_matches_commit_contents_even_on_a_stack_or_copy(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.chdir(directory):
            run.git("init", "-q")
            pin = '      {:playwright, "~> 1.65.0-rc.6", hex: :playwright_ex},\n'
            lock = '  "playwright": {:hex, :playwright_ex, "1.65.0-rc.6", ...},\n'
            for name in run.PLAYWRIGHT_SETUP_INPUTS:
                path = Path(name)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(pin if name == "mix.exs" else lock)

            def commit(subject):
                run.git("add", "-A")
                run.git("-c", "user.name=Test", "-c", "user.email=test@example.com",
                        "-c", "commit.gpgsign=false", "commit", "-qm", subject)
                return run.git("rev-parse", "HEAD")

            base = commit("base")
            self.assertFalse(run.privileged_setup_allowed(base, base, f"{run.PLAYWRIGHT_PILOT_BRANCH}1.65.0"))
            Path("mix.exs").write_text("  @version \"0.9.1\"\n" + pin)
            ordinary = commit("unrelated version change")
            self.assertTrue(run.privileged_setup_allowed(base, ordinary, "feature"))

            Path("mix.lock").write_text(lock.replace("-rc.6", ""))
            pilot = commit("updated package")
            Path("README.md").write_text("feature\n")
            stacked = commit("stacked feature")
            self.assertFalse(run.privileged_setup_allowed(base, pilot, "copied-update"))
            self.assertFalse(run.privileged_setup_allowed(base, stacked, "stacked-feature"))

            run.git("switch", "--detach", base)
            Path("mix.lock").write_text(lock.replace("-rc.6", "-rc.7"))
            newer_default = commit("default branch advances separately")
            self.assertTrue(run.privileged_setup_allowed(newer_default, ordinary, "feature"))
            self.assertFalse(run.privileged_setup_allowed(newer_default, stacked, "stacked-feature"))

            Path("mix.lock").write_text(lock)
            inventory = Path(run.PLAYWRIGHT_CLASSIFICATIONS)
            inventory.parent.mkdir(parents=True, exist_ok=True)
            inventory.write_text("{}\n")
            self.assertFalse(run.privileged_setup_allowed(base, commit("copied inventory"), "feature"))


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

    def test_reviewer_never_allows_writes(self):
        config = run.config()
        self.assertEqual(config["share"], "disabled")
        self.assertEqual(config["permissions"][0], run.permission("*", effect="deny"))
        self.assertEqual({rule["action"] for rule in config["permissions"] if rule["effect"] == "allow"},
                         {"read", "glob", "grep"})

    def test_review_locations_are_line_and_side_specific(self):
        diff = "@@ -12,2 +42,3 @@\n context\n-old\n+new\n+next\n\\ No newline at end of file"
        self.assertEqual(run.patch_lines(diff), {("RIGHT", 42), ("LEFT", 13), ("RIGHT", 43), ("RIGHT", 44)})
        with self.assertRaisesRegex(ValueError, "Reserved review marker"):
            run.text("Fake\n<!-- opencode-review: ... -->", 100)


class AppTokenTest(unittest.TestCase):
    def test_exchange_uses_explicit_user_agent(self):
        with (patch.dict(os.environ, {
                  "ACTIONS_ID_TOKEN_REQUEST_URL": "https://example.test/oidc?job=1",
                  "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "request-token",
              }),
              patch.object(run.urllib.request, "urlopen", side_effect=[
                  io.StringIO('{"value":"github-oidc"}'),
                  io.StringIO('{"token":"app-token"}'),
              ]) as open_url,
              patch.object(run, "gh") as gh,
              contextlib.redirect_stdout(io.StringIO()),
              run.app_token() as token):
            self.assertEqual(token, "app-token")
            request = open_url.call_args.args[0]
            self.assertEqual(request.get_header("User-agent"), "opencode")
            self.assertEqual(request.get_header("Authorization"), "Bearer github-oidc")
        gh.assert_called_once_with("api", "--method", "DELETE", "/installation/token",
                                   "--silent", token="app-token")


class PublishTest(unittest.TestCase):
    def pr(self, *, head="a" * 40, target="main", base="c" * 40, branch="feature"):
        return {"head": {"sha": head, "ref": branch, "repo": {"full_name": "ftes/fluffy"}},
                "base": {"ref": target, "sha": base}, "draft": False, "state": "open",
                "user": {"login": "alice", "type": "User"}}

    def setUp(self):
        self.enterContext(patch.object(run, "REPO", "ftes/fluffy"))

    def review(self, *, before=None, after=None, replay=False, prior=None):
        pr = self.pr()
        submitted = []
        remaining_reads = iter([pr, pr, before or pr, after or pr])

        def api(path, **kw):
            if "payload" in kw:
                submitted.append((path, kw["payload"]))
                return {"id": 12}
            if path == "pulls/42":
                return next(remaining_reads)
            if path == "pulls/42/reviews":
                return [{"body": submitted[0][1]["body"], "state": "APPROVED",
                         "user": {"type": "Bot", "login": run.BOT}}] if submitted else (prior or [])
            if path == "pulls/42/reviews/12":
                return {"state": "APPROVED"}
            if path == "pulls/42/files":
                return [{"filename": "lib/a.ex", "patch": "@@ -0,0 +1,1 @@\n+added"}]
            self.assertEqual(path, "issues/42/comments")
            return []

        with (patch.object(run, "api", side_effect=api),
              patch.object(run, "app_token", return_value=contextlib.nullcontext("app-token")),
              patch.object(run, "snapshot_diff", return_value=("b" * 40, "diff")),
              patch.object(run, "git", return_value=b"diff"),
              patch.object(run, "privileged_setup_allowed", return_value=True),
              patch.object(run, "gh") as gh, patch.object(run, "save"), patch.object(run, "context", return_value=pr),
              patch.object(run, "reconcile_reviews") as reconcile,
              contextlib.redirect_stdout(io.StringIO())):
            expected, marker, depth = run.prepare_review(42, pr["head"]["sha"])
            self.assertEqual(depth, "full")
            result = {
                "summary": "Checked calls", "open_blocking": 0, "open_non_blocking": 1,
                "findings": [{"path": " lib/a.ex ", "line": 1, "side": "RIGHT",
                              "body": "suggestion (non-blocking): Verify the result"}],
            }
            if replay:
                reconcile.side_effect = [ValueError("Cleanup failed"), None]
                with self.assertRaisesRegex(ValueError, "Cleanup failed"):
                    run.publish_review(42, expected, marker, result)
                remaining_reads = iter([pr, pr])
                self.assertIsNone(run.prepare_review(42, pr["head"]["sha"]))
                run.publish_review(42, expected, marker, result)
                self.assertEqual(reconcile.call_args_list, [call(42, token="app-token"), call(42)])
            else:
                run.publish_review(42, expected, marker, result)
                self.assertEqual(reconcile.call_count, int(before is None and after is None))
            self.assertTrue(any(arg.startswith("query=query(") for arg in gh.call_args.args))
        return submitted

    def test_review_posts_validated_path_and_marker_once_across_retries(self):
        writes = self.review(replay=True)
        self.assertEqual([path for path, _ in writes], ["pulls/42/reviews"])
        _, review = writes[0]
        self.assertEqual(review["event"], "APPROVE")
        self.assertEqual(review["commit_id"], self.pr()["head"]["sha"])
        self.assertEqual(review["comments"][0]["path"], "lib/a.ex")
        self.assertIn("Checked calls\n\n<!-- opencode-review:", review["body"])

    def test_review_rejects_changed_base_ref_or_sha_before_publishing(self):
        for changed in (self.pr(target="stable"), self.pr(base="d" * 40)):
            self.assertEqual(self.review(before=changed), [])

    def test_review_stops_if_the_head_branch_is_renamed_before_publishing(self):
        self.assertEqual(self.review(before=self.pr(branch=f"{run.PLAYWRIGHT_PILOT_BRANCH}1.65.0")), [])

    def test_stale_approval_is_dismissed_without_reviewing_the_new_head(self):
        writes = self.review(after=self.pr(head="d" * 40))
        self.assertEqual([path for path, _ in writes], ["pulls/42/reviews", "pulls/42/reviews/12/dismissals"])

    def marker(self, pr, *, legacy=False):
        head, target, base = run.snapshot(pr)
        merge_base = "b" * 40
        identity = "" if legacy else f" {hashlib.sha256(target.encode()).hexdigest()} {base}"
        return f"<!-- opencode-review: {head} {merge_base}{identity} -->"

    def test_previous_review_without_matching_recorded_base_requires_full_review(self):
        for legacy in (False, True):
            prior = {"body": self.marker(self.pr(base="e" * 40), legacy=legacy), "state": "APPROVED",
                     "user": {"type": "Bot", "login": run.BOT}}
            self.assertEqual(len(self.review(prior=[prior])), 1)

    def test_guard_excludes_exact_candidate_from_inference_and_publication(self):
        pr = self.pr(branch=f"{run.PLAYWRIGHT_PILOT_BRANCH}1.65.0")
        expected = run.snapshot(pr)
        marker = run.snapshot_marker(expected, "b" * 40)
        trusted = "e" * 40
        with (patch.object(run, "api", return_value=pr),
              patch.object(run, "previous_review", return_value=(None, False)),
              patch.object(run, "git", return_value=trusted),
              patch.object(run, "privileged_setup_allowed", return_value=False) as guard,
              patch.object(run, "snapshot_diff") as diff,
              patch.object(run, "app_token") as token,
              contextlib.redirect_stdout(io.StringIO())):
            self.assertIsNone(run.prepare_review(42, expected[0]))
            run.publish_review(42, expected, marker, None)
        self.assertEqual(guard.call_args_list, [call(trusted, expected[0], pr["head"]["ref"])] * 2)
        diff.assert_not_called()
        token.assert_not_called()

    def test_reconciliation_dismisses_superseded_app_verdicts_even_on_an_excluded_branch(self):
        pr = self.pr(branch=f"{run.PLAYWRIGHT_PILOT_BRANCH}1.65.0")
        app = {"login": run.BOT}
        reviews = [
            {"id": 1, "body": self.marker(self.pr(head="e" * 40)), "state": "APPROVED", "user": app},
            {"id": 2, "body": self.marker(self.pr(target="stable")), "state": "CHANGES_REQUESTED", "user": app},
            {"id": 3, "body": self.marker(pr), "state": "APPROVED", "user": app},
            {"id": 4, "body": self.marker(self.pr(target="stable")), "state": "APPROVED", "user": {"login": "alice"}},
        ]
        with (patch.object(run, "api", side_effect=[pr, reviews, pr]),
              patch.object(run, "app_token", return_value=contextlib.nullcontext("token")),
              patch.object(run, "snapshot_diff", return_value=("base", b"@@ -20 +20 @@\n-old\n+new\n")),
              patch.object(run, "reviewed_diff", return_value=b"@@ -1 +1 @@\n-old\n+new\n"),
              patch.object(run, "dismiss_review") as dismiss, patch.object(run, "agent") as agent):
            run.reconcile_reviews(42)
        self.assertEqual([call.args for call in dismiss.call_args_list],
                         [(42, 1, "token", run.STALE_VERDICT), (42, 2, "token", run.STALE_VERDICT)])
        agent.assert_not_called()

    def test_legacy_verdicts_only_dismissed_for_verified_retarget_or_replacement(self):
        pr = self.pr()
        head, _, _ = run.snapshot(pr)
        legacy = {"type": "Bot", "login": run.LEGACY_BOT}
        approval = {"id": 10, "body": "Verdict: OK to merge.", "state": "APPROVED",
                    "user": legacy, "commit_id": head, "submitted_at": "2026-11-26T10:00:00Z"}
        older_approval = dict(approval, id=14, commit_id="d" * 40)
        request = {"id": 11, "body": "Verdict: Issues found: 1 blocking, 0 non-blocking.",
                   "state": "CHANGES_REQUESTED", "user": legacy, "commit_id": "d" * 40}
        other_approval = dict(approval, id=12, body="An unrelated review")
        current = {"id": 13, "body": self.marker(pr), "state": "APPROVED", "user": {"login": run.BOT}}

        for retarget, new_review, expected in (
            (None, [], []),
            ("2026-11-26T09:59:00Z", [], []),
            ("2026-11-26T10:01:00Z", [], [(10, run.STALE_VERDICT), (14, run.STALE_VERDICT)]),
            (None, [current], [(11, run.REPLACED_VERDICT)]),
        ):
            reviews = [approval, request, other_approval, older_approval, *new_review]
            with (patch.object(run, "api", side_effect=[pr, reviews, pr]),
                  patch.object(run, "app_token", return_value=contextlib.nullcontext("token")),
                  patch.object(run, "last_retarget", return_value=retarget) as timeline,
                  patch.object(run, "dismiss_review") as dismiss):
                run.reconcile_reviews(42)
            timeline.assert_called_once_with(42, "main")
            self.assertEqual([call.args for call in dismiss.call_args_list],
                             [(42, review_id, "token", message) for review_id, message in expected])

    def test_draft_retarget_is_read_from_timeline_when_ready(self):
        draft = self.pr(target="stable") | {"draft": True}
        ready = draft | {"draft": False}
        approval = {
            "id": 1, "body": "Verdict: OK to merge.", "state": "APPROVED",
            "user": {"type": "Bot", "login": run.LEGACY_BOT}, "commit_id": ready["head"]["sha"],
            "submitted_at": "2026-11-26T10:00:00Z",
        }
        with (patch.object(run, "api", side_effect=[draft, ready, [approval], ready]),
              patch.object(run, "gh", return_value='{"createdAt":"2026-11-26T10:01:00Z","currentRefName":"stable"}') as gh,
              patch.object(run, "app_token", return_value=contextlib.nullcontext("token")),
              patch.object(run, "dismiss_review") as dismiss):
            run.reconcile_reviews(42)
            dismiss.assert_not_called()
            run.reconcile_reviews(42)
        self.assertTrue(any("BASE_REF_CHANGED_EVENT" in arg for arg in gh.call_args.args))
        dismiss.assert_called_once_with(42, 1, "token", run.STALE_VERDICT)

    def test_same_base_unchanged_diff_keeps_verdict_and_skips_model(self):
        pr = self.pr()
        previous = {"id": 1, "body": self.marker(self.pr(head="e" * 40)), "state": "APPROVED",
                    "user": {"type": "Bot", "login": run.BOT}}
        with (patch.object(run, "api", side_effect=[pr, [previous], pr, [], [previous]]),
              patch.object(run, "review_candidate_allowed", return_value=True),
              patch.object(run, "snapshot_diff", return_value=("b" * 40, b"same diff")),
              patch.object(run, "reviewed_diff", return_value=b"same diff"),
              patch.object(run, "app_token") as token,
              contextlib.redirect_stdout(io.StringIO())):
            run.reconcile_reviews(42)
            self.assertIsNone(run.prepare_review(42, pr["head"]["sha"]))
        token.assert_not_called()

    def test_unchanged_diff_retires_legacy_block_only_if_latest_verdict_approves(self):
        pr = self.pr()
        legacy = {"id": 1, "state": "CHANGES_REQUESTED", "user": {"type": "Bot", "login": run.LEGACY_BOT},
                  "body": "Verdict: Issues found: 1 blocking, 0 non-blocking."}
        approval = {"id": 2, "state": "APPROVED", "user": {"login": run.BOT},
                    "body": self.marker(self.pr(head="e" * 40))}
        request = dict(approval, id=3, state="CHANGES_REQUESTED", body=self.marker(pr))
        for newest in ([], [request]):
            with (patch.object(run, "api", side_effect=[pr, [legacy, approval, *newest], pr]),
                  patch.object(run, "snapshot_diff", return_value=("b" * 40, b"same diff")),
                  patch.object(run, "reviewed_diff", return_value=b"same diff"),
                  patch.object(run, "app_token", return_value=contextlib.nullcontext("token")),
                  patch.object(run, "dismiss_review") as dismiss):
                run.reconcile_reviews(42)
            if newest:
                dismiss.assert_not_called()
            else:
                dismiss.assert_called_once_with(42, 1, "token", run.REPLACED_VERDICT)
