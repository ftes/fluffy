import contextlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import improvement_pilot as pilot
import run


ORIGINAL = f"# Locators\n{pilot.SECTION}{pilot.ORIGINAL_PARAGRAPH}\n\nThe next paragraph.\n"
PROSE = 'Use the descendant filter. `button("Accio") |> or_(link("Accio"))` matches either.'
CHANGED = ORIGINAL.replace(pilot.ORIGINAL_PARAGRAPH, PROSE)
BASE = "a" * 40
HEAD = "b" * 40
TREE = "c" * 40
BRANCH = f"{run.IMPROVEMENT_PILOT_BRANCH}99"


class ImprovementPilotTest(unittest.TestCase):
    def test_model_may_decline_or_replace_one_paragraph(self):
        for result, expected in (({}, None), ({"paragraph": PROSE}, {pilot.DOC: CHANGED})):
            with (self.subTest(result=result), patch.object(pilot.update, "blob", return_value=ORIGINAL),
                  patch.object(pilot.playwright_pilot, "claude_json", return_value=result)):
                self.assertEqual(pilot.infer(BASE), expected)

    def test_an_already_reworded_paragraph_skips_inference(self):
        edited = ORIGINAL.replace("to check a collection", "to count all matches")
        with (patch.object(pilot.update, "blob", return_value=edited),
              patch.object(pilot.playwright_pilot, "claude_json") as model,
              contextlib.redirect_stdout(io.StringIO())):
            self.assertIsNone(pilot.infer(BASE))
        model.assert_not_called()
        with self.assertRaisesRegex(ValueError, "original paragraph has already changed"):
            pilot.validate_file(edited, edited.replace("to count all matches", "to check a collection"))

    def test_rejects_extra_files_and_markup(self):
        for file in (ORIGINAL, CHANGED + "\nNew material\n", CHANGED.replace(PROSE, "<script>bad</script>"),
                     CHANGED.replace(PROSE, "One line.\n\nSecond paragraph."),
                     CHANGED.replace(PROSE, "~~~elixir\nIO.puts(:bad)\n~~~")):
            with self.subTest(file=file), self.assertRaises(ValueError):
                pilot.validate_file(ORIGINAL, file)

        identity = {"repository": "ftes/fluffy", "run": "99", "base": BASE}
        data = identity | {"files": {pilot.DOC: CHANGED}, "tree": TREE}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "checked.json"
            pilot.write_artifact(path, data)
            self.assertEqual(pilot.read_files(path, identity, ORIGINAL, "tree"), data)
            for change in ({"base": HEAD}, {"files": data["files"] | {"mix.exs": "unexpected"}}):
                with self.subTest(change=change), self.assertRaises(ValueError):
                    pilot.write_artifact(path, data | change)
                    pilot.read_files(path, identity, ORIGINAL, "tree")

    def test_publish_requires_the_checked_tree_and_never_reuses_a_branch(self):
        files = {pilot.DOC: CHANGED}
        with (patch.object(pilot.update, "stage_replacements") as stage,
              patch.object(pilot.publish, "remote_head", side_effect=[HEAD, None]),
              patch.object(pilot.publish, "pull_requests", return_value=[]),
              patch.object(run, "git", return_value="unverified tree"),
              patch.object(run, "app_token") as token,
              contextlib.redirect_stdout(io.StringIO())):
            pilot.publish_draft(BASE, "main", "99", files, TREE)
            stage.assert_not_called()
            with self.assertRaisesRegex(ValueError, "checked tree"):
                pilot.publish_draft(BASE, "main", "99", files, TREE)
            token.assert_not_called()

    def test_publish_creates_one_draft_for_the_exact_base_and_head(self):
        repo = {"full_name": "ftes/fluffy"}
        created = {"head": {"ref": BRANCH, "sha": HEAD, "repo": repo},
                   "base": {"ref": "main", "sha": BASE, "repo": repo},
                   "user": {"login": run.BOT}, "state": "open", "draft": True,
                   "html_url": "https://example.invalid/draft"}
        with (patch.object(run, "REPO", "ftes/fluffy"),
              patch.object(pilot.update, "stage_replacements"),
              patch.object(pilot.publish, "remote_head", side_effect=[None, BASE, BASE, BASE, HEAD]),
              patch.object(pilot.publish, "pull_requests", return_value=[]),
              patch.object(run, "git", return_value=TREE),
              patch.object(pilot.publish, "commit", return_value=HEAD),
              patch.object(run, "app_token", return_value=contextlib.nullcontext("app")),
              patch.object(pilot.publish, "push") as push,
              patch.object(run, "api", return_value=created) as api,
              contextlib.redirect_stdout(io.StringIO())):
            pilot.publish_draft(BASE, "main", "99", {pilot.DOC: CHANGED}, TREE)
        push.assert_called_once_with(BRANCH, "app", "")
        api.assert_called_once_with("pulls", token="app", payload={
            "head": BRANCH, "base": "main", "draft": True, "title": pilot.TITLE, "body": pilot.BODY,
        })
