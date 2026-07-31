import asyncio
import json
import struct
import time

import numpy as np

from pose_host.main import (
    CapturedFrame,
    LatestCamera,
    LatestFrameSlot,
    PoseHostServer,
    StreamConfig,
    StreamPerformance,
    prepare_portrait_frame,
)
from pose_host.protocol import HEADER_LENGTH, PROTOCOL_VERSION, encode_packet


def decode(packet: bytes) -> tuple[dict, bytes]:
    header_length = HEADER_LENGTH.unpack(packet[:4])[0]
    header_end = 4 + header_length
    return json.loads(packet[4:header_end]), packet[header_end:]


def test_portrait_crop_resize_and_mirror_share_one_frame() -> None:
    source = np.zeros((4, 6, 3), dtype=np.uint8)
    source[:, 2] = 20
    source[:, 3] = 30

    transformed = prepare_portrait_frame(source, width=2, height=4, mirror=True)

    assert transformed.shape == (4, 2, 3)
    assert np.all(transformed[:, 0] == 30)
    assert np.all(transformed[:, 1] == 20)


def test_packet_contains_json_header_and_exact_jpeg_length() -> None:
    packet = encode_packet(
        frame_id=7,
        captured_at_ms=1234,
        image_width=360,
        image_height=480,
        inference_ms=42,
        landmarks=[{"x": 0.1, "y": 0.2, "z": 0.0, "visibility": 0.9, "presence": 0.8}],
        jpeg=b"jpeg",
    )

    header, jpeg = decode(packet)

    assert struct.unpack(">I", packet[:4])[0] > 0
    assert header["protocolVersion"] == PROTOCOL_VERSION
    assert header["frameId"] == 7
    assert header["capturedAtMs"] == 1234
    assert header["jpegLength"] == len(jpeg) == 4
    assert header["poseDetected"] is True
    assert jpeg == b"jpeg"


def test_latest_slot_drops_older_capture() -> None:
    slot = LatestFrameSlot()
    first = CapturedFrame(1, np.zeros((2, 2, 3), dtype=np.uint8))
    second = CapturedFrame(2, np.ones((2, 2, 3), dtype=np.uint8))
    slot.put(first)
    slot.put(second)

    selected = slot.take(0)

    assert selected is second
    assert slot.dropped == 1
    slot.close()


class FakeInferencer:
    def infer(self, image: np.ndarray) -> list[dict[str, float | None]]:
        return []


def test_generated_frame_ids_are_monotonic() -> None:
    server = PoseHostServer(FakeInferencer(), StreamConfig(preview_width=2, preview_height=4))
    captured = CapturedFrame(10, np.zeros((4, 2, 3), dtype=np.uint8))

    first, _ = decode(server._process(captured))
    second, _ = decode(server._process(captured))

    assert second["frameId"] == first["frameId"] + 1


def test_camera_is_retained_when_client_disconnects() -> None:
    class Camera:
        closed = False

        def take_latest(self, timeout_seconds: float) -> CapturedFrame:
            return CapturedFrame(10, np.zeros((4, 2, 3), dtype=np.uint8))

        def close(self) -> None:
            self.closed = True

    class Socket:
        async def send(self, packet: bytes) -> None:
            raise ConnectionError("client disconnected")

    camera = Camera()
    server = PoseHostServer(
        FakeInferencer(),
        StreamConfig(preview_width=2, preview_height=4),
        camera_factory=lambda: camera,
    )

    asyncio.run(server.handle(Socket()))

    assert camera.closed is False
    server.close()
    assert camera.closed is True


def test_reconnect_uses_same_camera_and_monotonic_frame_ids() -> None:
    class Camera:
        closed = False

        def take_latest(self, timeout_seconds: float) -> CapturedFrame:
            return CapturedFrame(10, np.zeros((4, 2, 3), dtype=np.uint8))

        def close(self) -> None:
            self.closed = True

    class Socket:
        def __init__(self) -> None:
            self.frame_ids: list[int] = []

        async def send(self, packet: bytes) -> None:
            header, _ = decode(packet)
            self.frame_ids.append(header["frameId"])
            raise ConnectionError("client disconnected")

    camera = Camera()
    factory_calls = 0

    def camera_factory() -> Camera:
        nonlocal factory_calls
        factory_calls += 1
        return camera

    server = PoseHostServer(
        FakeInferencer(),
        StreamConfig(preview_width=2, preview_height=4),
        camera_factory=camera_factory,
    )
    first = Socket()
    second = Socket()

    asyncio.run(server.handle(first))
    asyncio.run(server.handle(second))

    assert factory_calls == 1
    assert first.frame_ids == [1]
    assert second.frame_ids == [2]
    assert camera.closed is False
    server.close()


def test_single_capture_failure_retries_without_reopening_camera() -> None:
    class Capture:
        def __init__(self) -> None:
            self.read_count = 0
            self.released = False

        def read(self):
            self.read_count += 1
            time.sleep(0.005)
            if self.read_count == 1:
                return False, None
            return True, np.zeros((4, 2, 3), dtype=np.uint8)

        def release(self) -> None:
            self.released = True

    capture = Capture()
    factory_calls = 0

    def capture_factory() -> Capture:
        nonlocal factory_calls
        factory_calls += 1
        return capture

    camera = LatestCamera(
        0,
        StreamPerformance(),
        capture_factory=capture_factory,
        retry_delay_seconds=0.001,
    )

    frame = camera.take_latest(1.0)

    assert frame is not None
    assert factory_calls == 1
    assert capture.released is False
    camera.close()
