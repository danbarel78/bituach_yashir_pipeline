#!/usr/bin/env python3
"""Compute the pipeline version from ``base_version.json`` and the git state.

Branch-driven increment logic (see docs/versioning.md):

| branch / event     | computed version              | registry tags | deploys to |
|--------------------|-------------------------------|---------------|------------|
| feature/<name>     | X.Y.(Z+1)-<slug>.N+<sha>      | not pushed    | nothing    |
| bugfix/chore/docs  | X.Y.(Z+1)-<slug>.N+<sha>      | not pushed    | nothing    |
| refactor/test/     | X.Y.(Z+1)-<slug>.N+<sha>      | not pushed    | nothing    |
| dependabot/*       | X.Y.(Z+1)-<slug>.N+<sha>      | not pushed    | nothing    |
| develop            | X.Y.(Z+1)-dev.N+<sha>         | dev tags      | dev        |
| release/X.Y.Z      | X.Y.Z-rc.N+<sha>              | rc tags       | staging    |
| main + tag vX.Y.Z  | X.Y.Z (final)                 | vX.Y.Z        | prod       |
| hotfix/X.Y.Z       | X.Y.Z-hotfix.N+<sha>          | hotfix tags   | staging    |
| detached HEAD      | 0.0.0-local                   | not pushed    | nothing    |
| unknown branch     | refused (exit 1)              | -             | -          |

Feature-like branches use the *next* patch rather than the current one: after
``v1.0.0`` a feature build is ``1.0.1-<slug>.N``, which sorts above the tag.
Using the current patch would produce ``1.0.0-<slug>.N`` and the monotonicity
guard would reject every feature build once a release exists.

``N`` = ``BUILD_NUMBER`` (Jenkins); defaults to ``0`` for local builds.
``<sha>`` = 7-character commit SHA.

Guard rails (exit non-zero, never warn):
* strict SemVer validation of the computed version;
* monotonicity - the computed version must sort above the newest existing
  ``v*`` tag (the tagged ``main`` build itself is the only exception);
* ``main`` builds must carry a tag equal to ``base_version.json``, unless the
  project has never been released (base is ``0.0.0`` and ``releasedTag`` is
  null), in which case local scaffolding builds report ``0.0.0-local``.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE_VERSION_FILE = ROOT / "base_version.json"

SEMVER_RE = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)"
    r"(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?"
    r"(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$"
)
BASE_TAG_RE = re.compile(r"^v\d+\.\d+\.\d+$")

# Branches that produce a pre-release build and never deploy. They all share
# one rule: next patch + sanitised branch slug + build number + commit.
FEATURE_PREFIXES = (
    "feature/",
    "bugfix/",
    "chore/",
    "docs/",
    "refactor/",
    "test/",
    "dependabot/",
)

PrereleaseKey = tuple[tuple[int, int, str], ...]


def git(*args: str) -> str | None:
    """Run a git command in the repo root; return stripped stdout or None."""
    try:
        out = subprocess.run(
            ["git", *args], cwd=ROOT, capture_output=True, text=True, check=True
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    return out.stdout.strip()


def current_branch() -> str:
    """Branch name from CI env vars (Jenkins/GitHub) or the local checkout."""
    for var in ("GITHUB_REF_NAME", "GIT_BRANCH", "BRANCH_NAME"):
        val = os.environ.get(var)
        if val:
            return val.removeprefix("origin/")
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    return branch or "HEAD"


def commit_sha() -> str:
    sha = (
        os.environ.get("GIT_COMMIT")
        or os.environ.get("GITHUB_SHA")
        or git("rev-parse", "HEAD")
        or "0000000"
    )
    return sha[:7]


def build_number() -> int:
    raw = os.environ.get("BUILD_NUMBER", "0")
    try:
        return int(raw)
    except ValueError:
        sys.exit(f"BUILD_NUMBER must be an integer, got {raw!r}")


def load_base() -> tuple[int, int, int, str | None]:
    data = json.loads(BASE_VERSION_FILE.read_text(encoding="utf-8"))
    return (
        int(data["major"]),
        int(data["minor"]),
        int(data["patch"]),
        data.get("releasedTag"),
    )


def compute_version(
    branch: str, build: int, sha: str, base: tuple[int, int, int], released: str | None
) -> str:
    mj, mi, pa = base
    tag_ref = f"v{mj}.{mi}.{pa}"

    # Detached HEAD is a local convenience only: never pushed, never deployed.
    # It must be checked before the branch-name policy so a local experiment
    # does not have to pretend to be a branch.
    if branch in ("", "HEAD"):
        return "0.0.0-local"

    if branch == "main":
        exact = git("describe", "--exact-match", "--tags", "HEAD")
        if exact and BASE_TAG_RE.match(exact):
            if exact != tag_ref:
                sys.exit(
                    f"main tag {exact} does not equal base_version.json "
                    f"({tag_ref}) - refusing to build"
                )
            return f"{mj}.{mi}.{pa}"
        if (mj, mi, pa) == (0, 0, 0) and released is None:
            return "0.0.0-local"  # never released; scaffolding builds only
        sys.exit("main builds must come from a tag whose value equals base_version.json")

    if branch == "develop":
        return f"{mj}.{mi}.{pa + 1}-dev.{build}+{sha}"

    for prefix in FEATURE_PREFIXES:
        if branch.startswith(prefix):
            slug = re.sub(
                r"[^0-9a-zA-Z-]", "-", branch.removeprefix(prefix)
            ).strip("-")
            # Next patch, not the current one: 1.0.1-x sorts above v1.0.0.
            return f"{mj}.{mi}.{pa + 1}-{slug or 'feature'}.{build}+{sha}"

    if branch.startswith("release/"):
        m = re.fullmatch(r"release/(\d+)\.(\d+)\.(\d+)", branch)
        if not m:
            sys.exit(f"release branch must be named release/X.Y.0, got {branch!r}")
        return f"{m[1]}.{m[2]}.{m[3]}-rc.{build}+{sha}"

    if branch.startswith("hotfix/"):
        m = re.fullmatch(r"hotfix/(\d+)\.(\d+)\.(\d+)", branch)
        if not m:
            sys.exit(f"hotfix branch must be named hotfix/X.Y.Z, got {branch!r}")
        return f"{m[1]}.{m[2]}.{m[3]}-hotfix.{build}+{sha}"

    sys.exit(
        f"unsupported branch name: {branch!r}\n"
        "supported: develop, main, release/X.Y.Z, hotfix/X.Y.Z, "
        + ", ".join(f"{prefix}*" for prefix in FEATURE_PREFIXES)
    )


def version_key(version: str) -> tuple[tuple[int, int, int], tuple[int, PrereleaseKey]]:
    """Sort key implementing SemVer precedence (release > any prerelease)."""
    m = SEMVER_RE.match(version)
    if not m:
        sys.exit(f"internal error: {version!r} is not strict SemVer")
    core = (int(m[1]), int(m[2]), int(m[3]))
    if not m[4]:
        return (core, (1, ()))
    idents: list[tuple[int, int, str]] = []
    for ident in m[4].split("."):
        if ident.isdigit():
            idents.append((0, int(ident), ""))
        else:
            idents.append((1, 0, ident))
    return (core, (0, tuple(idents)))


def newest_tag() -> str | None:
    out = git("tag", "--sort=-v:refname") or ""
    for line in out.splitlines():
        name = line.strip()
        if name.startswith("v") and SEMVER_RE.match(name[1:]):
            return name
    return None


def check_monotonic(version: str, branch: str) -> None:
    newest = newest_tag()
    if newest is None:
        return
    computed = version_key(version)
    newest_key = version_key(newest.removeprefix("v"))
    if branch == "main" and computed >= newest_key:
        return  # the tagged production build itself
    if computed <= newest_key:
        sys.exit(
            f"version {version} does not sort above newest existing tag "
            f"{newest} - refusing to build"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Compute the pipeline version.")
    parser.add_argument("--json", action="store_true", help="print structured output")
    args = parser.parse_args()

    branch = current_branch()
    build = build_number()
    sha = commit_sha()
    major, minor, patch, released = load_base()

    version = compute_version(branch, build, sha, (major, minor, patch), released)
    if not SEMVER_RE.match(version):
        sys.exit(f"computed version {version!r} is not strict SemVer")
    check_monotonic(version, branch)

    if args.json:
        print(
            json.dumps(
                {"version": version, "branch": branch, "build": build, "gitSha": sha},
                sort_keys=True,
            )
        )
    else:
        print(version)


if __name__ == "__main__":
    main()
