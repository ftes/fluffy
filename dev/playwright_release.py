"""Discover PlaywrightEx releases or prepare a selected release locally."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
PROJECT = Path("mix.exs")
LOCK = Path("mix.lock")
OLDEST_LOCK = Path("mix.lock.oldest")
CONSUMER_LOCK = Path("integration/consumer/mix.lock")
LOCK_ENTRY = re.compile(r'^  "playwright": \{:hex, :playwright_ex, "([^"]+)"[^\n]*', re.M)
REQUIREMENT = re.compile(r'^([ \t]*\{:playwright, ")~> [^"]+(", hex: :playwright_ex\},)$', re.M)
VERSION = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?")


def version_key(version):
    match = VERSION.fullmatch(version)
    if not match:
        raise ValueError(f"Invalid PlaywrightEx version: {version!r}")
    prerelease = match[4]
    parts = () if prerelease is None else tuple(
        (0, int(part)) if part.isdigit() else (1, part) for part in prerelease.split(".")
    )
    return (int(match[1]), int(match[2]), int(match[3]), prerelease is None, parts)


def lock_entry(path):
    entries = LOCK_ENTRY.findall(path.read_text())
    if len(entries) != 1:
        raise ValueError(f"Expected one PlaywrightEx Hex entry in {path}")
    version_key(entries[0])
    return entries[0]


def discover():
    response = subprocess.check_output([
        "curl", "-fsSL", "--retry", "3", "--max-time", "20", "https://hex.pm/api/packages/playwright_ex"
    ])
    latest = json.loads(response)["latest_version"]
    locked = lock_entry(LOCK)
    print(f"PlaywrightEx: locked {locked}, latest on Hex {latest}.")
    if version_key(latest) <= version_key(locked):
        return
    if output := os.environ.get("GITHUB_OUTPUT"):
        with Path(output).open("a") as stream:
            stream.write(f"locked={locked}\nlatest={latest}\n")
    else:
        print(f"To prepare: python3 dev/playwright_release.py prepare {latest}")


def mix(*args, cwd=".", **env):
    subprocess.run(["mix", *args], cwd=cwd, env=os.environ | {"MIX_ENV": "test"} | env, check=True)


def prepare(release):
    version_key(release)
    originals = {path: path.read_text() for path in (PROJECT, LOCK, OLDEST_LOCK, CONSUMER_LOCK)}
    config = originals[PROJECT]
    if len(REQUIREMENT.findall(config)) != 1:
        raise ValueError(f"Expected one PlaywrightEx requirement in {PROJECT}")
    lock_entry(OLDEST_LOCK)

    try:
        # Resolve the chosen version, even when Hex already has a later compatible one.
        PROJECT.write_text(REQUIREMENT.sub(rf"\g<1>== {release}\g<2>", config))
        mix("deps.update", "playwright")
        mix("deps.update", "playwright", cwd=CONSUMER_LOCK.parent)
        for path in (LOCK, CONSUMER_LOCK):
            if lock_entry(path) != release:
                raise ValueError(f"Expected PlaywrightEx {release} in {path}")

        newest = LOCK.read_text()
        entry = LOCK_ENTRY.search(newest)[0]
        floor = LOCK_ENTRY.sub(lambda _: entry, originals[OLDEST_LOCK])
        PROJECT.write_text(REQUIREMENT.sub(rf"\g<1>~> {release}\g<2>", config))
        # Keep the other floors pinned and check the lock from an empty deps directory.
        LOCK.write_text(floor)
        with tempfile.TemporaryDirectory() as deps:
            mix("deps.get", "--check-locked", MIX_DEPS_PATH=deps)
        if LOCK.read_text() != floor:
            raise ValueError("Resolving the oldest dependencies changed the floor lockfile")
        OLDEST_LOCK.write_text(floor)
        LOCK.write_text(newest)
    except (Exception, KeyboardInterrupt):
        for path, content in originals.items():
            path.write_text(content)
        raise

    mix("setup")
    mix("usage_rules.sync", "--yes")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("discover")
    commands.add_parser("prepare").add_argument("version")
    args = parser.parse_args()
    os.chdir(ROOT)
    try:
        if args.command == "discover":
            discover()
        else:
            prepare(args.version)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
