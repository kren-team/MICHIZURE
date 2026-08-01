from __future__ import annotations

import json
import os
from itertools import islice
from typing import Iterable

import firebase_admin
from firebase_admin import auth, credentials, firestore, messaging

from .service import DeviceTarget

ANDROID_NOTIFICATION_CHANNEL_ID = "michizure_alerts_v1"


def _chunks(values: list[DeviceTarget], size: int) -> Iterable[list[DeviceTarget]]:
    iterator = iter(values)
    while chunk := list(islice(iterator, size)):
        yield chunk


def build_multicast_message(
    targets: list[DeviceTarget],
    title: str,
    body: str,
    data: dict[str, str],
) -> messaging.MulticastMessage:
    return messaging.MulticastMessage(
        notification=messaging.Notification(title=title, body=body),
        data=data,
        android=messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                channel_id=ANDROID_NOTIFICATION_CHANNEL_ID,
                priority="high",
                default_sound=True,
                default_vibrate_timings=True,
            ),
        ),
        tokens=[target.token for target in targets],
    )


class FirebaseNotificationBackend:
    def __init__(self) -> None:
        project_id = os.environ.get("FIREBASE_PROJECT_ID")
        raw_credentials = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")
        credential = (
            credentials.Certificate(json.loads(raw_credentials))
            if raw_credentials
            else credentials.ApplicationDefault()
        )
        try:
            firebase_admin.get_app()
        except ValueError:
            options = {"projectId": project_id} if project_id else None
            firebase_admin.initialize_app(credential, options)
        self._db = firestore.client()

    def verify_id_token(self, token: str) -> str:
        decoded = auth.verify_id_token(token)
        uid = decoded.get("uid")
        if not isinstance(uid, str) or not uid:
            raise ValueError("missing uid")
        return uid

    def get_debt(self, debt_id: str) -> dict | None:
        snapshot = self._db.collection("debts").document(debt_id).get()
        return snapshot.to_dict() if snapshot.exists else None

    def get_contribution(self, debt_id: str, contribution_id: str) -> dict | None:
        snapshot = (
            self._db.collection("debts")
            .document(debt_id)
            .collection("contributionEvents")
            .document(contribution_id)
            .get()
        )
        return snapshot.to_dict() if snapshot.exists else None

    def is_group_member(self, group_id: str, user_id: str) -> bool:
        return (
            self._db.collection("groups")
            .document(group_id)
            .collection("members")
            .document(user_id)
            .get()
            .exists
        )

    def group_member_ids(self, group_id: str) -> list[str]:
        members = (
            self._db.collection("groups")
            .document(group_id)
            .collection("members")
            .stream()
        )
        return [member.id for member in members]

    def enabled_devices(self, user_ids: list[str]) -> list[DeviceTarget]:
        targets: list[DeviceTarget] = []
        for user_id in user_ids:
            devices = (
                self._db.collection("users")
                .document(user_id)
                .collection("devices")
                .where("enabled", "==", True)
                .stream()
            )
            for device in devices:
                token = device.to_dict().get("token")
                if isinstance(token, str) and token:
                    targets.append(DeviceTarget(user_id, device.id, token))
        return targets

    def reserve_event(self, event_id: str, event_type: str, source_id: str) -> bool:
        reference = self._db.collection("notificationEvents").document(event_id)
        transaction = self._db.transaction()

        @firestore.transactional
        def reserve(current_transaction) -> bool:
            snapshot = reference.get(transaction=current_transaction)
            if snapshot.exists:
                return False
            current_transaction.create(
                reference,
                {
                    "eventType": event_type,
                    "sourceId": source_id,
                    "createdAt": firestore.SERVER_TIMESTAMP,
                },
            )
            return True

        return reserve(transaction)

    def send(
        self,
        targets: list[DeviceTarget],
        title: str,
        body: str,
        data: dict[str, str],
    ) -> list[DeviceTarget]:
        invalid: list[DeviceTarget] = []
        for chunk in _chunks(targets, 500):
            response = messaging.send_each_for_multicast(
                build_multicast_message(chunk, title, body, data)
            )
            for target, result in zip(chunk, response.responses, strict=True):
                if not result.success and isinstance(
                    result.exception,
                    (messaging.UnregisteredError, messaging.SenderIdMismatchError),
                ):
                    invalid.append(target)
        return invalid

    def disable_devices(self, targets: list[DeviceTarget]) -> None:
        batch = self._db.batch()
        for target in targets:
            reference = (
                self._db.collection("users")
                .document(target.user_id)
                .collection("devices")
                .document(target.device_id)
            )
            batch.update(
                reference,
                {"enabled": False, "updatedAt": firestore.SERVER_TIMESTAMP},
            )
        batch.commit()
