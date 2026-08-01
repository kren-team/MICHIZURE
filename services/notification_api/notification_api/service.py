from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Protocol


class NotificationError(Exception):
    pass


class Unauthorized(NotificationError):
    pass


class NotFound(NotificationError):
    pass


class Forbidden(NotificationError):
    pass


class InvalidEvent(NotificationError):
    pass


@dataclass(frozen=True)
class DeviceTarget:
    user_id: str
    device_id: str
    token: str


@dataclass(frozen=True)
class DeliveryResult:
    event_id: str
    duplicate: bool
    recipient_device_count: int


class NotificationBackend(Protocol):
    def verify_id_token(self, token: str) -> str: ...

    def get_debt(self, debt_id: str) -> dict | None: ...

    def get_contribution(self, debt_id: str, contribution_id: str) -> dict | None: ...

    def is_group_member(self, group_id: str, user_id: str) -> bool: ...

    def group_member_ids(self, group_id: str) -> list[str]: ...

    def enabled_devices(self, user_ids: list[str]) -> list[DeviceTarget]: ...

    def reserve_event(self, event_id: str, event_type: str, source_id: str) -> bool: ...

    def send(
        self,
        targets: list[DeviceTarget],
        title: str,
        body: str,
        data: dict[str, str],
    ) -> list[DeviceTarget]: ...

    def disable_devices(self, targets: list[DeviceTarget]) -> None: ...


class NotificationService:
    def __init__(self, backend: NotificationBackend) -> None:
        self._backend = backend

    def authenticate(self, token: str) -> str:
        if not token:
            raise Unauthorized()
        try:
            return self._backend.verify_id_token(token)
        except Exception as error:
            raise Unauthorized() from error

    def debt_created(self, caller_uid: str, debt_id: str) -> DeliveryResult:
        debt = self._debt_for_member(caller_uid, debt_id)
        if debt.get("failedUserId") != caller_uid:
            raise Forbidden()
        return self._deliver(
            caller_uid=caller_uid,
            group_id=debt["groupId"],
            event_type="debt-created",
            source_id=debt_id,
            debt_id=debt_id,
            title="新しい負債が発生しました",
            body="グループのスクワット返済が追加されました。",
        )

    def contribution_created(
        self,
        caller_uid: str,
        debt_id: str,
        contribution_id: str,
    ) -> DeliveryResult:
        debt = self._debt_for_member(caller_uid, debt_id)
        contribution = self._backend.get_contribution(debt_id, contribution_id)
        if contribution is None:
            raise NotFound()
        if contribution.get("userId") != caller_uid:
            raise Forbidden()
        return self._deliver(
            caller_uid=caller_uid,
            group_id=debt["groupId"],
            event_type="contribution-created",
            source_id=contribution_id,
            debt_id=debt_id,
            contribution_id=contribution_id,
            title="救済が進みました",
            body="グループメンバーがスクワット返済に貢献しました。",
        )

    def debt_completed(self, caller_uid: str, debt_id: str) -> DeliveryResult:
        debt = self._debt_for_member(caller_uid, debt_id)
        if debt.get("status") != "completed":
            raise InvalidEvent()
        return self._deliver(
            caller_uid=caller_uid,
            group_id=debt["groupId"],
            event_type="debt-completed",
            source_id=debt_id,
            debt_id=debt_id,
            title="負債を完済しました",
            body="グループのスクワット返済が完了しました。",
        )

    def _debt_for_member(self, caller_uid: str, debt_id: str) -> dict:
        debt = self._backend.get_debt(debt_id)
        if debt is None:
            raise NotFound()
        group_id = debt.get("groupId")
        if not isinstance(group_id, str) or not group_id:
            raise InvalidEvent()
        if not self._backend.is_group_member(group_id, caller_uid):
            raise Forbidden()
        return debt

    def _deliver(
        self,
        *,
        caller_uid: str,
        group_id: str,
        event_type: str,
        source_id: str,
        debt_id: str,
        title: str,
        body: str,
        contribution_id: str | None = None,
    ) -> DeliveryResult:
        event_id = hashlib.sha256(f"{event_type}:{source_id}".encode()).hexdigest()
        if not self._backend.reserve_event(event_id, event_type, source_id):
            return DeliveryResult(event_id, True, 0)
        recipients = [
            uid
            for uid in self._backend.group_member_ids(group_id)
            if uid != caller_uid
        ]
        targets = self._backend.enabled_devices(recipients)
        data = {"eventType": event_type, "debtId": debt_id}
        if contribution_id is not None:
            data["contributionId"] = contribution_id
        invalid = self._backend.send(targets, title, body, data) if targets else []
        if invalid:
            self._backend.disable_devices(invalid)
        return DeliveryResult(event_id, False, len(targets))
