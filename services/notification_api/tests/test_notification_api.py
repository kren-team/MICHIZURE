from fastapi.testclient import TestClient

from notification_api.main import app, get_service
from notification_api.service import DeviceTarget, NotificationService


class FakeBackend:
    def __init__(self) -> None:
        self.reserved: set[str] = set()
        self.sent: list[tuple[list[DeviceTarget], dict[str, str]]] = []
        self.disabled: list[DeviceTarget] = []
        self.invalid: list[DeviceTarget] = []
        self.debt = {
            "groupId": "group-1",
            "failedUserId": "alice",
            "status": "active",
        }

    def verify_id_token(self, token: str) -> str:
        if token != "valid-token":
            raise ValueError("invalid")
        return "alice"

    def get_debt(self, debt_id: str) -> dict | None:
        return self.debt if debt_id == "debt-1" else None

    def get_contribution(self, debt_id: str, contribution_id: str) -> dict | None:
        if debt_id == "debt-1" and contribution_id == "contribution-1":
            return {"userId": "alice"}
        return None

    def is_group_member(self, group_id: str, user_id: str) -> bool:
        return group_id == "group-1" and user_id in {"alice", "bob"}

    def group_member_ids(self, group_id: str) -> list[str]:
        return ["alice", "bob"]

    def enabled_devices(self, user_ids: list[str]) -> list[DeviceTarget]:
        return [DeviceTarget("bob", "device-bob", "token-bob")]

    def reserve_event(self, event_id: str, event_type: str, source_id: str) -> bool:
        if event_id in self.reserved:
            return False
        self.reserved.add(event_id)
        return True

    def send(self, targets, title, body, data):
        self.sent.append((targets, data))
        return self.invalid

    def disable_devices(self, targets: list[DeviceTarget]) -> None:
        self.disabled.extend(targets)


def test_health_and_authenticated_debt_created() -> None:
    backend = FakeBackend()
    app.dependency_overrides[get_service] = lambda: NotificationService(backend)
    client = TestClient(app)

    assert client.get("/health").json() == {"status": "ok"}
    response = client.post(
        "/v1/notifications/debt-created",
        headers={"Authorization": "Bearer valid-token"},
        json={"debtId": "debt-1"},
    )

    assert response.status_code == 200
    assert response.json()["status"] == "sent"
    assert response.json()["recipientDeviceCount"] == 1
    assert backend.sent[0][0][0].user_id == "bob"
    app.dependency_overrides.clear()


def test_rejects_missing_auth_and_client_controlled_content() -> None:
    backend = FakeBackend()
    app.dependency_overrides[get_service] = lambda: NotificationService(backend)
    client = TestClient(app)

    assert client.post(
        "/v1/notifications/debt-created", json={"debtId": "debt-1"}
    ).status_code == 401
    assert client.post(
        "/v1/notifications/debt-created",
        headers={"Authorization": "Bearer valid-token"},
        json={
            "debtId": "debt-1",
            "title": "spoofed",
            "uid": "bob",
            "token": "target-token",
        },
    ).status_code == 422
    app.dependency_overrides.clear()


def test_contribution_is_idempotent_and_disables_invalid_device() -> None:
    backend = FakeBackend()
    backend.invalid = [DeviceTarget("bob", "device-bob", "token-bob")]
    service = NotificationService(backend)

    first = service.contribution_created("alice", "debt-1", "contribution-1")
    second = service.contribution_created("alice", "debt-1", "contribution-1")

    assert not first.duplicate
    assert second.duplicate
    assert len(backend.sent) == 1
    assert backend.disabled == backend.invalid


def test_completed_debt_uses_separate_event_type() -> None:
    backend = FakeBackend()
    backend.debt["status"] = "completed"
    service = NotificationService(backend)

    completed = service.debt_completed("alice", "debt-1")
    created = service.debt_created("alice", "debt-1")

    assert completed.event_id != created.event_id
    assert len(backend.sent) == 2
