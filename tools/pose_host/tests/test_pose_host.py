import asyncio
import json
import struct

import numpy as np

from pose_host.main import (
    CapturedFrame,
    LatestFrameSlot,
    PoseHostServer,
    StreamConfig,
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


def test_camera_is_released_when_client_disconnects() -> None:
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

    assert camera.closed is True
