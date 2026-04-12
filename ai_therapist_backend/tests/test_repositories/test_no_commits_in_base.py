"""Acceptance test: BaseRepository must not call commit/rollback.

Migrated repositories (user, user_identity, session, reminder) are an
intentional exception — they preserve legacy behavior for callers in
auth.py / main.py and will be normalized in Uplift_App-4xc. The base
class itself, however, must enforce the policy.
"""
from __future__ import annotations

from pathlib import Path

REPOSITORIES_DIR = Path(__file__).resolve().parents[2] / "app" / "repositories"


def test_base_has_no_commit_or_rollback():
    """Strip docstrings, then check for actual commit/rollback calls."""
    import ast

    source = (REPOSITORIES_DIR / "base.py").read_text()
    tree = ast.parse(source)

    forbidden = {"commit", "rollback"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            assert node.func.attr not in forbidden, (
                f"base.py calls {node.func.attr}() at line {node.lineno} — "
                "BaseRepository must never commit or rollback."
            )
