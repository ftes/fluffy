import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
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
    def pr(self, *, head="a" * 40, target="main", base="c" * 40, branch="opencode/nightly-42"):
        return {"head": {"sha": head, "ref": branch, "repo": {"full_name": "ftes/fluffy"}},
                "base": {"ref": target, "sha": base}, "draft": False, "state": "open",
                "user": {"login": "alice", "type": "User"}}

    def setUp(self):
        self.enterContext(patch.object(run, "REPO", "ftes/fluffy"))

    def test_triage_rejects_out_of_scope_pr_before_any_write(self):
        decisions = [{"number": 42, "action": "close", "why": "Obsolete"},
                     {"number": 123, "action": "close", "why": "Different PR"}]
        with (patch.dict(os.environ, NUMBERS="42 56"),
              patch.object(run, "context", return_value=self.pr()), patch.object(run, "save"),
              patch.object(run, "snapshot_diff", return_value=("base", "diff")),
              patch.object(run, "open_nightly", return_value=self.pr()),
              patch.object(run, "agent", return_value={"decisions": decisions}),
              patch.object(run, "app_token") as token):
            with self.assertRaisesRegex(ValueError, "Invalid triage PR"):
                run.triage("Triage")
        token.assert_not_called()

    def test_triage_carries_inspected_head_and_skips_a_stale_close(self):
        pr = self.pr()
        decisions = [{"number": 42, "action": "close", "why": "Obsolete"},
                     {"number": 56, "action": "redo", "why": "Moved code"}]
        with (patch.dict(os.environ, NUMBERS="42 56"),
              patch.object(run, "context") as context, patch.object(run, "save"),
              patch.object(run, "snapshot_diff", return_value=("base", "diff")) as snapshot_diff,
              patch.object(run, "open_nightly", side_effect=[pr, pr, None, pr]) as eligible,
              patch.object(run, "agent", return_value={"decisions": decisions}),
              patch.object(run, "app_token", return_value=contextlib.nullcontext("token")),
              patch.object(run, "close") as close, patch.object(run, "output") as output):
            run.triage("Triage")
        close.assert_not_called()
        self.assertIs(context.call_args.kwargs["item"], pr)
        self.assertIs(snapshot_diff.call_args.args[0], pr)
        self.assertEqual(eligible.call_args_list[2].kwargs, {
            "number": 42, "branch": pr["head"]["ref"], "head": pr["head"]["sha"], "base": pr["base"]["sha"],
        })
        self.assertEqual(json.loads(output.call_args.kwargs["redo"]), [{
            "number": 56, "branch": pr["head"]["ref"], "head": pr["head"]["sha"],
            "base": pr["base"]["sha"], "why": "Moved code",
        }])

    def review(self, *, before=None, after=None, replay=False, prior=None):
        pr = self.pr()
        submitted = []
        remaining_reads = iter([pr, before or pr, after or pr])

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
              patch.object(run, "agent", return_value={
                  "summary": "Checked calls", "open_blocking": 0, "open_non_blocking": 1,
                  "findings": [{"path": " lib/a.ex ", "line": 1, "side": "RIGHT",
                                "body": "suggestion (non-blocking): Verify the result"}],
              }) as agent,
              patch.object(run, "snapshot_diff", return_value=("b" * 40, "diff")),
              patch.object(run, "gh") as gh, patch.object(run, "save"), patch.object(run, "context", return_value=pr),
              contextlib.redirect_stdout(io.StringIO())):
            run.review(42, pr["head"]["sha"], "Review")
            if replay:
                remaining_reads = iter([pr])
                run.review(42, pr["head"]["sha"], "Review")
            agent.assert_called_once()
            self.assertIn("Review mode: full.", agent.call_args.args[1])
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

    def test_reconciliation_dismisses_superseded_app_verdicts_before_model_access(self):
        pr = self.pr()
        app = {"login": run.BOT}
        reviews = [
            {"id": 1, "body": self.marker(self.pr(head="e" * 40)), "state": "APPROVED", "user": app},
            {"id": 2, "body": self.marker(self.pr(target="stable")), "state": "CHANGES_REQUESTED", "user": app},
            {"id": 3, "body": self.marker(pr), "state": "APPROVED", "user": app},
            {"id": 4, "body": self.marker(self.pr(target="stable")), "state": "APPROVED", "user": {"login": "alice"}},
        ]
        with (patch.object(run, "api", side_effect=[pr, reviews, pr]),
              patch.object(run, "app_token", return_value=contextlib.nullcontext("token")),
              patch.object(run, "dismiss_review") as dismiss, patch.object(run, "agent") as agent):
            run.reconcile_reviews(42)
        self.assertEqual([call.args for call in dismiss.call_args_list], [(42, 1, "token"), (42, 2, "token")])
        agent.assert_not_called()

    def test_eligibility_rejects_changed_base_at_publication(self):
        pr = self.pr()
        branch = pr["head"]["ref"]
        head = pr["head"]["sha"]
        with patch.object(run, "bots_only", return_value=True), patch.object(run, "api", return_value=pr):
            self.assertIs(run.open_nightly(42, branch, head, base=pr["base"]["sha"]), pr)
            self.assertIsNone(run.open_nightly(42, branch, head, base="d" * 40))

    def test_nonpublication_outcomes_can_omit_unused_fields(self):
        self.assertEqual(run.new_pr_result("improve", {"action": "none", "body": "No good idea"}),
                         ("none", "", "No good idea"))
        self.assertEqual(run.new_pr_result("recreate", {"action": "close", "title": "Obsolete"}),
                         ("close", "Obsolete", ""))
        with self.assertRaises(ValueError):
            run.new_pr_result("improve", {"action": "publish", "title": "Simplify"})

    def test_stage_rejects_rename_out_of_protected_path(self):
        with tempfile.TemporaryDirectory() as tmp, contextlib.chdir(tmp):
            run.git("init", "-q")
            path = Path(".github/workflows/test.yml")
            path.parent.mkdir(parents=True)
            path.write_text("name: test\n")
            run.git("add", "-A")
            run.git("-c", "user.name=test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false",
                    "commit", "-qm", "initial")
            path.rename("unprotected.yml")
            with self.assertRaisesRegex(ValueError, "cannot publish workflow"):
                run.stage(run.git("rev-parse", "HEAD"))

    def test_recover_pushed_commit_and_create_missing_pr(self):
        branch = "opencode/issue-12-99"
        marker = "OpenCode-Publish: 99 opencode/issue-12-99"
        sha = "a" * 40
        commit = {"message": f"Improve the docs\n\nExplain the behavior.\n\n{marker}\n",
                  "author": {"email": run.BOT_EMAIL}}
        pr = self.pr(head=sha, branch=branch)
        pr["html_url"] = "https://example.test/pull/555"
        pr["user"]["login"] = run.BOT
        with (patch.object(run, "remote_head", return_value=sha),
              patch.object(run, "api", side_effect=[commit, [], pr, [pr]]) as api):
            recovered = run.recover_branch(branch, marker)
            self.assertEqual(run.publish_branch(branch, "main", recovered, "token", issue=12),
                             (pr["html_url"], True))
            self.assertEqual(run.publish_branch(branch, "main", recovered, "token", issue=12),
                             (pr["html_url"], True))
        writes = [call for call in api.call_args_list if "payload" in call.kwargs]
        self.assertEqual(len(writes), 1)
        self.assertEqual(writes[0].kwargs["payload"]["body"], "Explain the behavior.\n\nRefs #12")
        with (patch.object(run, "remote_head", return_value=sha), patch.object(run, "api", return_value=commit)):
            with self.assertRaisesRegex(ValueError, "does not belong"):
                run.recover_branch(branch, "OpenCode-Publish: different run")

    def test_absent_remote_ref_is_distinct_from_transport_error(self):
        with patch.object(run, "git", side_effect=subprocess.CalledProcessError(2, "git")):
            self.assertIsNone(run.remote_head("test"))
        with patch.object(run, "git", side_effect=subprocess.CalledProcessError(128, "git")):
            with self.assertRaises(subprocess.CalledProcessError):
                run.remote_head("test")

    def test_exhaustion_uses_latest_ci_run_and_fresh_eligibility(self):
        item = {"number": 42, "head": "a" * 40, "branch": "opencode/nightly-42"}
        view = {"headRefOid": item["head"], "mergeable": "MERGEABLE"}

        def ci(id, status, conclusion, number=42):
            return {"id": id, "created_at": f"2026-11-26T00:00:0{id}Z", "status": status,
                    "conclusion": conclusion, "head_repository": {"full_name": "ftes/fluffy"},
                    "pull_requests": [{"number": number}]}

        failure = ci(1, "completed", "failure")
        running = ci(2, "in_progress", None)
        unrelated = ci(3, "completed", "failure", number=56)
        passed = ci(2, "completed", "success")
        with (patch.dict(os.environ, MAX_COMMITS="3", EXHAUSTED=json.dumps([item]), GH_TOKEN="token"),
              patch.object(run, "gh", return_value=json.dumps(view)),
              patch.object(run, "api", side_effect=[
                  {"workflow_runs": [failure, running]}, {"workflow_runs": [unrelated, passed]},
                  {"workflow_runs": [failure]}, {"workflow_runs": [failure]},
              ]),
              patch.object(run, "open_nightly", side_effect=[False, True]) as eligible,
              patch.object(run, "close") as close):
            run.exhausted()  # CI is retrying
            run.exhausted()  # Another PR using the same branch failed, but this PR passed
            run.exhausted()  # no longer eligible
            close.assert_not_called()
            run.exhausted()
        self.assertEqual(eligible.call_count, 2)
        self.assertEqual(eligible.call_args.kwargs, dict(item, min_commits=3))
        close.assert_called_once()

    def test_recovered_replacement_does_not_close_after_human_takeover(self):
        old = self.pr()
        with (patch.dict(os.environ, GITHUB_RUN_ID="99", OLD_BRANCH=old["head"]["ref"],
                         OLD_HEAD=old["head"]["sha"], OLD_BASE=old["base"]["sha"], REDO_WHY="Moved code"),
              patch.object(run, "git"), patch.object(run, "open_nightly", side_effect=[True, True, False]),
              patch.object(run, "recover_branch", return_value=("new-sha", "New title", "Body")),
              patch.object(run, "app_token", return_value=contextlib.nullcontext("token")),
              patch.object(run, "publish_branch", return_value=("https://example.test/pull/43", True)) as publish,
              patch.object(run, "agent") as agent, patch.object(run, "close") as close,
              contextlib.redirect_stdout(io.StringIO())):
            run.new_pr("recreate", "opencode/nightly-99-42", "Prompt", 42)
        publish.assert_called_once()
        agent.assert_not_called()
        close.assert_not_called()

    def test_fresh_playwright_run_validates_and_recovers_the_release_commit(self):
        branch = "opencode/playwright-ex-1.65.0"
        sha = "a" * 40
        commit = {"message": f"Update PlaywrightEx to 1.65.0\n\nBody\n\nOpenCode-Publish: 900 {branch}\n",
                  "author": {"email": run.BOT_EMAIL}}
        with (patch.dict(os.environ, GITHUB_RUN_ID="901"),
              patch.object(run, "remote_head", return_value=sha), patch.object(run, "api", return_value=commit),
              patch.object(run, "ensure_commit"), patch.object(run, "validate_playwright_version") as version):
            marker = run.publish_marker(branch)
            self.assertEqual(run.recover_branch(branch, marker, release="1.65.0"),
                             (sha, "Update PlaywrightEx to 1.65.0", "Body"))
            version.assert_called_once_with("1.65.0", revision=sha)
            with self.assertRaisesRegex(ValueError, "does not belong"):
                run.recover_branch(branch, marker)

    def test_playwright_floor_must_match_requested_version(self):
        with tempfile.TemporaryDirectory() as tmp, contextlib.chdir(tmp):
            Path("integration/consumer").mkdir(parents=True)
            lock = '  "playwright": {:hex, :playwright_ex, "1.65.0", ...}\n'
            Path("mix.lock").write_text(lock)
            Path("integration/consumer/mix.lock").write_text(lock)
            floor = Path("mix.lock.oldest")
            floor.write_text(lock.replace("1.65.0", "1.65.0-rc.6"))
            with self.assertRaisesRegex(ValueError, "mix.lock.oldest"):
                run.validate_playwright_version("1.65.0")
            floor.write_text(lock)
            run.validate_playwright_version("1.65.0")
