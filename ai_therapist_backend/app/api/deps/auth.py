"""Authentication dependencies for FastAPI endpoints."""
from __future__ import annotations

import hashlib
import logging
import time
from dataclasses import dataclass
from typing import Any, Dict, Optional

import requests
from fastapi import Depends, HTTPException, Request, status
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from app.core.config import settings
from app.crud import user as crud_user
from app.crud import user_identity as crud_user_identity
from app.db.session import get_db
from app.models.user import User

logger = logging.getLogger(__name__)

_GOOGLE_CERTS_URL = (
    "https://www.googleapis.com/robot/v1/metadata/x509/"
    "securetoken@system.gserviceaccount.com"
)
_CERT_CACHE_TTL_SECONDS = 60 * 60  # 1 hour
_cert_cache: Dict[str, Any] = {}
_cert_cache_expiry: float = 0.0

_DEFAULT_PROVIDER = "firebase"


@dataclass
class AuthenticatedUser:
    user: User
    token: str
    provider: str
    payload: Dict[str, Any]


def _ensure_firebase_initialized() -> None:
    try:
        import firebase_admin

        if firebase_admin._apps:
            return

        try:
            firebase_admin.initialize_app()
        except Exception as exc:  # noqa: BLE001
            logger.debug("Firebase admin initialization failed: %s", exc)
    except ImportError:
        # firebase_admin not installed; skip initialization
        pass


def _verify_with_firebase_admin(token: str) -> Optional[Dict[str, Any]]:
    try:
        import firebase_admin
        from firebase_admin import auth as firebase_auth

        _ensure_firebase_initialized()
        if not firebase_admin._apps:
            return None

        return firebase_auth.verify_id_token(token)
    except Exception as exc:  # noqa: BLE001
        logger.debug("Firebase admin verification failed: %s", exc)
        return None


def _refresh_google_certs() -> Dict[str, Any]:
    global _cert_cache, _cert_cache_expiry

    current_time = time.time()
    if _cert_cache and current_time < _cert_cache_expiry:
        return _cert_cache

    try:
        response = requests.get(_GOOGLE_CERTS_URL, timeout=10)
        response.raise_for_status()
        _cert_cache = response.json()
        _cert_cache_expiry = current_time + _CERT_CACHE_TTL_SECONDS
        return _cert_cache
    except requests.RequestException as exc:
        logger.error("Failed to refresh Google certs: %s", exc)
        return {}


def _verify_with_google_keys(token: str) -> Optional[Dict[str, Any]]:
    keys = _refresh_google_certs()
    if not keys:
        return None

    try:
        unverified_header = jwt.get_unverified_header(token)
        kid = unverified_header.get("kid")
        if not kid or kid not in keys:
            logger.debug("JWT header missing or unknown kid")
            return None

        unverified_claims = jwt.get_unverified_claims(token)
        audience = (
            settings.FIREBASE_AUTH_AUDIENCE
            or settings.FIREBASE_PROJECT_ID
            or unverified_claims.get("aud")
        )
        project_id = settings.FIREBASE_PROJECT_ID or unverified_claims.get("aud")
        if not audience or not project_id:
            logger.debug("Unable to determine Firebase audience/project ID")
            return None

        issuer = f"https://securetoken.google.com/{project_id}"
        public_key = keys[kid]

        payload = jwt.decode(
            token,
            public_key,
            algorithms=["RS256"],
            audience=audience,
            issuer=issuer,
        )
        return payload
    except JWTError as exc:
        logger.debug("Google key verification failed: %s", exc)
        return None
    except Exception as exc:  # noqa: BLE001
        logger.debug("Unexpected error during Google key verification: %s", exc)
        return None


def _verify_with_local_secret(token: str) -> Optional[Dict[str, Any]]:
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=["HS256"])
        return payload
    except JWTError as exc:
        logger.debug("Local secret verification failed: %s", exc)
        return None


def _verify_token(token: str) -> Optional[tuple]:
    """Returns (payload, provider) or None."""
    payload = _verify_with_firebase_admin(token)
    if payload:
        return payload, "firebase"

    payload = _verify_with_google_keys(token)
    if payload:
        return payload, "google"

    # Local SECRET_KEY fallback is dev-only. Never allow in production —
    # anyone who knows the key can forge arbitrary JWTs.
    from app.core.environment import env_settings
    if not env_settings.is_production:
        payload = _verify_with_local_secret(token)
        if payload:
            return payload, "local"

    return None


def _normalize_email(provider: str, uid: str, email: Optional[str]) -> str:
    """Generate a stable, unique email alias for a given identity."""

    normalized_provider = (provider or _DEFAULT_PROVIDER).replace("@", "_").replace(":", "_")
    digest_source = f"{normalized_provider}:{uid}"
    digest = hashlib.sha256(digest_source.encode("utf-8")).hexdigest()[:16]

    if email:
        sanitized = email.strip().lower()
        if "@" in sanitized:
            local_part, domain = sanitized.split("@", 1)
            # Preserve original domain while making the local part unique per identity.
            return f"{local_part}+{normalized_provider}-{digest}@{domain}"
        return f"{sanitized}+{normalized_provider}-{digest}"

    # Fall back to a synthetic address when email is unavailable (e.g., phone auth).
    return f"{normalized_provider}-{digest}@auth.local"


def _get_or_create_user(
    db: Session,
    *,
    provider: str,
    uid: str,
    email: Optional[str],
    name: Optional[str],
) -> User:
    identity = crud_user_identity.get_by_provider_uid(db, provider=provider, uid=uid)
    if identity:
        user = identity.user
        if email and identity.email != email:
            identity.email = email
            db.commit()
        return user

    normalized_email = _normalize_email(provider, uid, email)

    user = crud_user.create(
        db,
        email=normalized_email,
        name=name,
    )
    identity = crud_user_identity.create(
        db,
        user_id=user.id,
        provider=provider,
        uid=uid,
        email=email,
    )
    logger.info(
        "Created new isolated user_id=%s for provider=%s uid=%s",
        user.id,
        provider,
        uid,
    )
    return identity.user


async def get_current_user(
    request: Request,
    db: Session = Depends(get_db),
) -> AuthenticatedUser:
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.lower().startswith("bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")

    token = auth_header.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid bearer token")

    result = _verify_token(token)
    if not result:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid authentication credentials")

    payload, provider = result

    uid = payload.get("user_id") or payload.get("sub") or payload.get("uid")
    if not uid:
        logger.warning("Authenticated token missing UID")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid authentication credentials")

    email = payload.get("email")
    name = payload.get("name")

    try:
        user = _get_or_create_user(
            db,
            provider=provider,
            uid=uid,
            email=email,
            name=name,
        )
    except Exception as exc:  # noqa: BLE001
        logger.error("Failed to load or create user for uid=%s: %s", uid, exc)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Unable to load user") from exc

    return AuthenticatedUser(
        user=user,
        token=token,
        provider=provider,
        payload=payload,
    )
