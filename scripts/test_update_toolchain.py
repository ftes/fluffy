import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from update_toolchain import latest_patch, update


class ToolchainTest(unittest.TestCase):
    def test_only_stable_patches_for_matching_otp(self):
        self.assertEqual(latest_patch("1.20.4-otp-29", [
            "1.20.5-otp-29", "1.20.9-otp-28", "1.21.0-otp-29",
            "1.20.6-rc.1-otp-29", "1.20.7", "2.0.0-otp-29",
        ]), "1.20.5-otp-29")

    def test_numeric_order_and_erlang_four_part_versions(self):
        self.assertEqual(latest_patch("27.3.4.9", [
            "27.3.4.10", "27.3.4.8", "28.0.0",
        ]), "27.3.4.10")
        self.assertEqual(latest_patch("26.8.1", ["26.8.10", "26.9.0"]), "26.8.10")

    def test_never_downgrades(self):
        self.assertEqual(latest_patch("11.19.0", ["11.18.9", "11.19.0-rc.1"]), "11.19.0")

    def test_update_is_synchronized_and_repeatable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tools = root / ".tool-versions"
            tools.write_text("elixir 1.20.4-otp-29\nerlang 29.0.6\nnodejs 26.8.1\npnpm 11.19.0\n")
            package = root / "package.json"
            package.write_text('{"packageManager": "pnpm@11.19.0", "engines": {"node": ">=20"}}')
            catalogs = {
                "elixir": "1.20.5-otp-29", "erlang": "29.0.7",
                "nodejs": "26.8.2", "pnpm": "11.19.1",
            }
            def remote(command, **kwargs):
                return subprocess.CompletedProcess(command, 0, catalogs[command[-1]])
            with patch("update_toolchain.subprocess.run", side_effect=remote):
                before = (tools.read_text(), package.read_text())
                update(root, dry_run=True)
                self.assertEqual(before, (tools.read_text(), package.read_text()))
                update(root)
                first = (tools.read_text(), package.read_text())
                update(root)
                self.assertEqual(first, (tools.read_text(), package.read_text()))
            self.assertIn("elixir 1.20.5-otp-29", tools.read_text())
            self.assertIn("pnpm 11.19.1", tools.read_text())
            self.assertEqual(json.loads(package.read_text()), {
                "packageManager": "pnpm@11.19.1", "engines": {"node": ">=20"},
            })
            with patch("update_toolchain.subprocess.run", side_effect=[
                subprocess.CompletedProcess([], 0, "1.20.6-otp-29"),
                subprocess.CalledProcessError(1, "mise"),
            ]):
                with self.assertRaises(subprocess.CalledProcessError):
                    update(root)
            self.assertEqual(first, (tools.read_text(), package.read_text()))


if __name__ == "__main__":
    unittest.main()
