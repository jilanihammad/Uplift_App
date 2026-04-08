"""
Backward-compatibility shim.

The streaming pipeline has been decomposed into the app.services.pipeline package.
This module re-exports all public symbols so existing imports continue to work.
"""

from app.services.pipeline import *  # noqa: F401,F403
