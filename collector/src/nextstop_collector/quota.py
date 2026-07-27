"""Quota accounting.

TfNSW publishes a 60,000 call/day limit but offers no endpoint to check consumption,
so the api_call_log table is the only source of truth. Every attempt counts, including
retries.
"""

from datetime import date

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .storage.models import ApiCallLog


class QuotaExhausted(RuntimeError):
    pass


def calls_used(session: Session, provider: str, day: date) -> int:
    stmt = select(func.count(ApiCallLog.id)).where(
        ApiCallLog.provider == provider,
        ApiCallLog.quota_date == day,
    )
    return session.execute(stmt).scalar_one()


def check_quota(session: Session, provider: str, day: date, limit: int) -> tuple[int, bool]:
    """Return (calls used today, whether we are into the last 20% of the allowance)."""
    used = calls_used(session, provider, day)
    if used >= limit:
        raise QuotaExhausted(
            f"{provider} quota exhausted for {day}: {used}/{limit} calls already logged"
        )
    return used, used >= int(limit * 0.8)
