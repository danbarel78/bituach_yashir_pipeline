"""Unit tests for the pipeline version policy (ci/scripts/version.py).

These are pure-function tests: no git repository state, no network, no
container. The only git-dependent branches are exercised by monkeypatching
``version.git`` so the tests stay deterministic on any machine and in CI.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "version.py"
_spec = importlib.util.spec_from_file_location("pipeline_version", SCRIPT)
assert _spec and _spec.loader
version = importlib.util.module_from_spec(_spec)
sys.modules["pipeline_version"] = version
_spec.loader.exec_module(version)

BASE = (1, 2, 3)
SHA = "abc1234"
BUILD = 7


@pytest.mark.parametrize(
    ("branch", "expected"),
    [
        ("feature/login-timeout", "1.2.4-login-timeout.7+abc1234"),
        ("bugfix/session-expiry", "1.2.4-session-expiry.7+abc1234"),
        ("chore/bump-deps", "1.2.4-bump-deps.7+abc1234"),
        ("docs/secrets", "1.2.4-secrets.7+abc1234"),
        ("refactor/downstream", "1.2.4-downstream.7+abc1234"),
        ("test/coverage", "1.2.4-coverage.7+abc1234"),
    ],
)
def test_feature_like_branches_get_next_patch(branch: str, expected: str) -> None:
    assert version.compute_version(branch, BUILD, SHA, BASE, "v1.2.3") == expected


def test_slug_sanitises_slashes_and_dots() -> None:
    result = version.compute_version(
        "dependabot/pip/httpx-0.28", BUILD, SHA, BASE, "v1.2.3"
    )
    assert result == "1.2.4-pip-httpx-0-28.7+abc1234"


def test_feature_version_is_strict_semver() -> None:
    result = version.compute_version("feature/x", BUILD, SHA, BASE, "v1.2.3")
    assert version.SEMVER_RE.match(result)


def test_feature_version_sorts_above_last_release() -> None:
    result = version.compute_version("feature/x", BUILD, SHA, BASE, "v1.2.3")
    assert version.version_key(result) > version.version_key("1.2.3")


def test_develop_uses_next_patch_and_dev_prerelease() -> None:
    assert version.compute_version("develop", 42, SHA, BASE, "v1.2.3") == (
        "1.2.4-dev.42+abc1234"
    )


def test_release_branch_encodes_its_own_version() -> None:
    assert version.compute_version("release/2.0.0", 9, SHA, BASE, "v1.2.3") == (
        "2.0.0-rc.9+abc1234"
    )


@pytest.mark.parametrize("branch", ["release/2.0", "release/2.0.0-rc1"])
def test_release_branch_requires_full_semver(branch: str) -> None:
    with pytest.raises(SystemExit):
        version.compute_version(branch, BUILD, SHA, BASE, "v1.2.3")


def test_hotfix_branch_encodes_its_own_version() -> None:
    assert version.compute_version("hotfix/1.2.4", 3, SHA, BASE, "v1.2.3") == (
        "1.2.4-hotfix.3+abc1234"
    )


def test_hotfix_branch_requires_full_semver() -> None:
    with pytest.raises(SystemExit):
        version.compute_version("hotfix/1.2", BUILD, SHA, BASE, "v1.2.3")


def test_detached_head_is_local_only() -> None:
    assert version.compute_version("HEAD", BUILD, SHA, BASE, None) == "0.0.0-local"
    assert version.compute_version("", BUILD, SHA, BASE, None) == "0.0.0-local"


def test_unknown_branch_is_refused() -> None:
    with pytest.raises(SystemExit, match="unsupported branch name"):
        version.compute_version("spike/cache", BUILD, SHA, BASE, "v1.2.3")


def test_main_untagged_after_release_is_refused(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(version, "git", lambda *args: None)
    with pytest.raises(SystemExit, match="must come from a tag"):
        version.compute_version("main", BUILD, SHA, BASE, "v1.2.3")


def test_main_tagged_and_matching_base_is_final(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(version, "git", lambda *args: "v1.2.3")
    assert version.compute_version("main", BUILD, SHA, BASE, "v1.2.3") == "1.2.3"


def test_main_tag_mismatch_is_refused(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(version, "git", lambda *args: "v1.2.4")
    with pytest.raises(SystemExit, match="does not equal base_version.json"):
        version.compute_version("main", BUILD, SHA, BASE, "v1.2.3")


def test_never_released_main_is_local(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(version, "git", lambda *args: None)
    assert version.compute_version("main", BUILD, SHA, (0, 0, 0), None) == (
        "0.0.0-local"
    )


def test_semver_precedence_orders_dev_rc_release() -> None:
    dev = version.version_key("1.2.4-dev.5+x")
    rc = version.version_key("1.2.4-rc.2+x")
    release = version.version_key("1.2.4")
    assert dev < rc < release