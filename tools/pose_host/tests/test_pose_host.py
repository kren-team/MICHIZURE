import asyncio
import json

from pose_host.main import LatestFrameSlot
from pose_host.protocol import HEADER, MAGIC, FrameMessage, decode_frame, encode_result


def frame(frame_id: int) -> FrameMessage:
    return FrameMessage(frame_id, 1234 + frame_id, 320, 240, 90, b"jpeg")


def test_binary_frame_is_received() -> None:
    raw = HEADER.pack(MAGIC, 7, 1234, 320, 240, 90, 4) + b"jpeg"

    decoded = decode_frame(raw)

    assert decoded.frame_id == 7
    assert decoded.timestamp_ms == 1234
    assert decoded.jpeg == b"jpeg"
    assert decoded.rotation_degrees == 90


def test_landmark_json_keeps_frame_id() -> None:
    payload = json.loads(
        encode_result(
            frame(8),
            inference_ms=42,
            image_width=240,
            image_height=320,
            landmarks=[
                {
                    "x": 0.1,
                    "y": 0.2,
                    "z": -0.3,
                    "visibility": 0.9,
                    "presence": 0.8,
                }
            ],
        )
    )

    assert payload["frameId"] == 8
    assert payload["timestamp"] == 1242
    assert payload["landmarks"][0]["visibility"] == 0.9


def test_latest_frame_replaces_older_pending_frame() -> None:
    async def scenario() -> None:
        slot = LatestFrameSlot()
        await slot.put(frame(1))
        await slot.put(frame(2))

        selected = await slot.take()

        assert selected is not None
        assert selected.frame_id == 2
        assert slot.dropped == 1
        await slot.close()

    asyncio.run(scenario())
