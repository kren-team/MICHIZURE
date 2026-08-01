from __future__ import annotations

from functools import lru_cache
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, Field

from .firebase_backend import FirebaseNotificationBackend
from .service import (
    DeliveryResult,
    Forbidden,
    InvalidEvent,
    NotFound,
    NotificationService,
    Unauthorized,
)


class DebtRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    debtId: str = Field(min_length=1, max_length=150)


class ContributionRequest(DebtRequest):
    contributionId: str = Field(min_length=1, max_length=240)


class DeliveryResponse(BaseModel):
    eventId: str
    status: str
    recipientDeviceCount: int


@lru_cache
def get_service() -> NotificationService:
    return NotificationService(FirebaseNotificationBackend())


bearer = HTTPBearer(auto_error=False)


def authenticated_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    service: Annotated[NotificationService, Depends(get_service)],
) -> str:
    try:
        return service.authenticate(credentials.credentials if credentials else "")
    except Unauthorized as error:
        raise HTTPException(status_code=401, detail="unauthorized") from error


def _response(result: DeliveryResult) -> DeliveryResponse:
    return DeliveryResponse(
        eventId=result.event_id,
        status="duplicate" if result.duplicate else "sent",
        recipientDeviceCount=result.recipient_device_count,
    )


def _translate(action):
    try:
        return _response(action())
    except NotFound as error:
        raise HTTPException(status_code=404, detail="not found") from error
    except Forbidden as error:
        raise HTTPException(status_code=403, detail="forbidden") from error
    except InvalidEvent as error:
        raise HTTPException(status_code=409, detail="invalid event state") from error


app = FastAPI(title="MICHIZURE Notification API", version="1.0.0")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/v1/notifications/debt-created", response_model=DeliveryResponse)
def debt_created(
    request: DebtRequest,
    uid: Annotated[str, Depends(authenticated_user)],
    service: Annotated[NotificationService, Depends(get_service)],
) -> DeliveryResponse:
    return _translate(lambda: service.debt_created(uid, request.debtId))


@app.post("/v1/notifications/contribution-created", response_model=DeliveryResponse)
def contribution_created(
    request: ContributionRequest,
    uid: Annotated[str, Depends(authenticated_user)],
    service: Annotated[NotificationService, Depends(get_service)],
) -> DeliveryResponse:
    return _translate(
        lambda: service.contribution_created(
            uid, request.debtId, request.contributionId
        )
    )


@app.post("/v1/notifications/debt-completed", response_model=DeliveryResponse)
def debt_completed(
    request: DebtRequest,
    uid: Annotated[str, Depends(authenticated_user)],
    service: Annotated[NotificationService, Depends(get_service)],
) -> DeliveryResponse:
    return _translate(lambda: service.debt_completed(uid, request.debtId))
