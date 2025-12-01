"""Datetime helpers for consistent ISO8601 serialization."""

from datetime import datetime, timezone


def serialize_datetime(dt: datetime) -> str:
    """Return an RFC3339-compliant UTC timestamp."""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    else:
        dt = dt.astimezone(timezone.utc)
    return dt.isoformat().replace("+00:00", "Z")


def utcnow_isoformat() -> str:
    """Convenience wrapper for datetime.utcnow()."""
    return serialize_datetime(datetime.now(tz=timezone.utc))
