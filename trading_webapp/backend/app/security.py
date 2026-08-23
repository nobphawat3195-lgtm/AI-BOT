"""Shared-secret auth for every mutating and account-visible endpoint."""

from __future__ import annotations

import hmac

from fastapi import Header, HTTPException, status

from .config import get_settings


async def require_token(x_api_token: str = Header(default="")) -> None:
    """Reject requests whose ``X-API-Token`` header does not match."""
    expected = get_settings().api_token
    # Compared in constant time so the token cannot be probed byte by byte.
    if not hmac.compare_digest(x_api_token, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid or missing X-API-Token",
        )
