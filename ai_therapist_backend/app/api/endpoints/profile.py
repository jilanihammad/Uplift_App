from __future__ import annotations

from fastapi import APIRouter, Depends, Header, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.api.deps.auth import AuthenticatedUser, get_current_user
from app.db.session import get_db
from app.schemas import ProfileResponse, ProfileUpdateRequest
from app.services.profile_service import ProfileConflictError, get_profile, upsert_profile

router = APIRouter()


def _make_etag(version: int) -> str:
    return f'W/"v{version}"'


def _parse_if_match(etag: str) -> int:
    if not etag:
        raise HTTPException(status_code=status.HTTP_428_PRECONDITION_REQUIRED, detail="If-Match header required")

    value = etag.strip()
    if value.startswith("W/\"") and value.endswith("\""):
        value = value[3:-1]
    if value.startswith("v"):
        value = value[1:]
    if not value.isdigit():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid If-Match header")
    return int(value)


@router.get("", response_model=ProfileResponse)
async def read_profile(
    response: Response,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ProfileResponse:
    profile = get_profile(db, user_id=current_user.user.id)
    if profile is None:
        response.headers["ETag"] = _make_etag(0)
        return ProfileResponse(version=0)

    response.headers["ETag"] = _make_etag(profile.version or 0)
    return ProfileResponse(
        preferred_name=profile.preferred_name,
        pronouns=profile.pronouns,
        locale=profile.locale,
        version=profile.version or 0,
        updated_at=profile.updated_at,
    )


@router.put("", response_model=ProfileResponse)
async def update_profile(
    payload: ProfileUpdateRequest,
    response: Response,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
    if_match: str = Header(..., alias="If-Match"),
) -> ProfileResponse:
    expected_version = _parse_if_match(if_match)

    existing = get_profile(db, user_id=current_user.user.id)
    if existing is None and expected_version != 0:
        raise HTTPException(status_code=status.HTTP_412_PRECONDITION_FAILED, detail="Profile does not exist")

    data = payload.model_dump(exclude_unset=True)

    preferred_name = data.get("preferred_name", existing.preferred_name if existing else None)
    pronouns = data.get("pronouns", existing.pronouns if existing else None)
    locale = data.get("locale", existing.locale if existing else None)

    service_expected_version = expected_version if existing is not None else None

    try:
        profile = upsert_profile(
            db,
            user_id=current_user.user.id,
            preferred_name=preferred_name,
            pronouns=pronouns,
            locale=locale,
            expected_version=service_expected_version,
        )
    except ProfileConflictError:
        raise HTTPException(status_code=status.HTTP_412_PRECONDITION_FAILED, detail="Profile version mismatch") from None

    response.headers["ETag"] = _make_etag(profile.version or 0)
    return ProfileResponse(
        preferred_name=profile.preferred_name,
        pronouns=profile.pronouns,
        locale=profile.locale,
        version=profile.version or 0,
        updated_at=profile.updated_at,
    )
