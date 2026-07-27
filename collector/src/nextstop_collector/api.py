"""Ground-truth ingest.

Two iOS Shortcuts on the home screen POST here — one for boarding, one for arrival.

Optional. The headline Phase 0 result comes from TfNSW's own realtime feed, which needs
no help from you. This adds the stronger claim: that the realtime estimate matched what
actually happened, rather than merely differing from the timetable.
"""

import secrets
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Literal

from fastapi import Depends, FastAPI, Header, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select

from .config import get_settings
from .storage.db import init_db, session_scope
from .storage.models import Observation
from .timeutil import now_utc, to_sydney


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    init_db()
    yield


app = FastAPI(title="NextStop collector", version="0.1.0", lifespan=lifespan)


class ObservationIn(BaseModel):
    event: Literal["boarded", "arrived"]
    corridor: str = Field(min_length=1, max_length=64)
    note: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    # Shortcuts can send the real time if the phone was offline when it happened.
    recorded_at: datetime | None = None


class ObservationOut(BaseModel):
    id: int
    event: str
    corridor: str
    recorded_at: datetime
    local_time: str


def require_token(x_nextstop_token: str = Header(default="")) -> None:
    expected = get_settings().ingest_token
    if not expected:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "NEXTSTOP_INGEST_TOKEN is not configured on the server",
        )
    if not secrets.compare_digest(x_nextstop_token, expected):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "bad or missing X-NextStop-Token")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "time": now_utc().isoformat()}


@app.post("/observations", response_model=ObservationOut, dependencies=[Depends(require_token)])
def create_observation(payload: ObservationIn) -> ObservationOut:
    moment = payload.recorded_at or now_utc()
    if moment.tzinfo is None:
        raise HTTPException(422, "recorded_at needs a timezone")

    with session_scope() as session:
        observation = Observation(
            recorded_at=moment,
            event=payload.event,
            corridor=payload.corridor,
            note=payload.note,
            latitude=payload.latitude,
            longitude=payload.longitude,
        )
        session.add(observation)
        session.flush()
        return ObservationOut(
            id=observation.id,
            event=observation.event,
            corridor=observation.corridor,
            recorded_at=observation.recorded_at,
            local_time=to_sydney(moment).strftime("%Y-%m-%d %H:%M:%S %Z"),
        )


@app.get(
    "/observations/recent",
    response_model=list[ObservationOut],
    dependencies=[Depends(require_token)],
)
def recent_observations(limit: int = 20) -> list[ObservationOut]:
    with session_scope() as session:
        rows = session.execute(
            select(Observation).order_by(Observation.recorded_at.desc()).limit(limit)
        ).scalars()
        return [
            ObservationOut(
                id=row.id,
                event=row.event,
                corridor=row.corridor,
                recorded_at=row.recorded_at,
                local_time=to_sydney(row.recorded_at).strftime("%Y-%m-%d %H:%M:%S %Z"),
            )
            for row in rows
        ]
