"""Update stable patches in .tool-versions using mise's remote version catalog."""

import argparse
import json
from pathlib import Path
import re
import subprocess

TOOLS = ("elixir", "erlang", "nodejs", "pnpm")
VERSION = re.compile(r"(\d+\.\d+\.\d+(?:\.\d+)*)(-otp-\d+)?")


def parse_version(value):
    match = VERSION.fullmatch(value)
    if not match:
        raise ValueError(f"Unsupported stable version: {value}")
    return tuple(map(int, match[1].split("."))), match[2] or ""


def latest_patch(current, available):
    numbers, suffix = parse_version(current)
    candidates = [(numbers, current)]
    for version in available:
        if not VERSION.fullmatch(version):
            continue
        candidate, candidate_suffix = parse_version(version)
        if candidate[:2] == numbers[:2] and candidate_suffix == suffix:
            candidates.append((candidate, version))
    return max(candidates)[1]


def update(root, dry_run=False):
    tools_path = root / ".tool-versions"
    original = tools_path.read_text()
    pins = {}
    for tool in TOOLS:
        matches = re.findall(rf"^{tool}\s+(\S+)\s*$", original, re.MULTILINE)
        if len(matches) != 1:
            raise ValueError(f"Expected exactly one {tool} pin")
        pins[tool] = matches[0]
    _, suffix = parse_version(pins["elixir"])
    otp, _ = parse_version(pins["erlang"])
    if suffix != f"-otp-{otp[0]}":
        raise ValueError("Elixir's OTP suffix must match Erlang's major version")

    # Resolve every tool before writing anything, so a catalog failure leaves files intact.
    updated = {}
    for tool, current in pins.items():
        result = subprocess.run(
            ["mise", "ls-remote", tool], check=True, capture_output=True,
            text=True, timeout=180,
        )
        available = result.stdout.split()
        if not available:
            raise ValueError(f"Empty remote catalog for {tool}")
        updated[tool] = latest_patch(current, available)
        print(f"{tool}: {current} -> {updated[tool]}")

    content = original
    for tool, version in updated.items():
        content = re.sub(
            rf"^({tool}[ \t]+)\S+", lambda m: m[1] + version,
            content, flags=re.MULTILINE,
        )
    package_path = root / "package.json"
    package = json.loads(package_path.read_text())
    package["packageManager"] = f"pnpm@{updated['pnpm']}"
    if not dry_run:
        tools_path.write_text(content)
        package_path.write_text(json.dumps(package, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    update(Path(__file__).resolve().parent.parent, args.dry_run)
