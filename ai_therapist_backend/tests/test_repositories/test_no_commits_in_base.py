"""Acceptance test: repositories must not call commit/rollback.

Legacy repositories migrated from app/crud/ (user, user_identity, session,
reminder) are an intentional exception — they preserve commit-on-write
behavior for callers in auth.py / main.py and will be normalized in
Uplift_App-4xc. Every other repository (including BaseRepository) must
enforce the no-commit policy.
"""
from __future__ import annotations

import ast
from pathlib import Path

REPOSITORIES_DIR = Path(__file__).resolve().parents[2] / "app" / "repositories"

# Allow-list: legacy migrated repos that may commit until Uplift_App-4xc.
LEGACY_COMMIT_ALLOWED = {
    "user_repository.py",
    "user_identity_repository.py",
    "session_repository.py",
    "reminder_repository.py",
}

# Files that have no DB calls at all; skipping them keeps the failure
# message focused when regressions land.
NO_SCAN_NEEDED = {"__init__.py"}

FORBIDDEN = {"commit", "rollback"}


def _assert_no_commit_or_rollback(path: Path) -> None:
    tree = ast.parse(path.read_text())
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            assert node.func.attr not in FORBIDDEN, (
                f"{path.name} calls {node.func.attr}() at line {node.lineno} — "
                "this repository must never commit or rollback (services own UoW)."
            )


def test_base_has_no_commit_or_rollback():
    _assert_no_commit_or_rollback(REPOSITORIES_DIR / "base.py")


def test_new_repositories_have_no_commit_or_rollback():
    """Every non-legacy repository file must be commit-free."""
    for path in sorted(REPOSITORIES_DIR.glob("*.py")):
        if path.name in NO_SCAN_NEEDED or path.name in LEGACY_COMMIT_ALLOWED:
            continue
        if path.name == "base.py":
            continue  # covered by test_base_has_no_commit_or_rollback
        _assert_no_commit_or_rollback(path)
