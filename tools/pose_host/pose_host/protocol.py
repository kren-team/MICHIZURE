from __future__ import annotations

import json
import struct
from dataclasses import dataclass
from typing import Any

MAGIC = 0x4D504831  # MPH1
HEADER = struct.Struct(">Iqqiiii")


@dataclass(frozen=True)
class FrameMessage:
    frame_id: int
    timestamp_ms: int
    image_width: int
    image_height: int
    rotation_degrees: int
    jpeg: bytes


def decode_frame(message: bytes) -> FrameMessage:
    if len(message) < HEADER.size:
        raise ValueError("frame is shorter than the protocol header")
    magic, frame_id, timestamp_ms, width, height, rotation, jpeg_size = HEADER.unpack_from(
        message
    )
    if magic != MAGIC:
        raise ValueError("invalid frame magic")
    jpeg = message[HEADER.size :]
    if jpeg_size != len(jpeg) or width <= 0 or height <= 0:
        raise ValueError("invalid frame dimensions or JPEG size")
    if rotation not in (0, 90, 180, 270):
        raise ValueError("invalid rotation")
    return FrameMessage(frame_id, timestamp_ms, width, height, rotation, jpeg)


def encode_result(
    frame: FrameMessage,
    *,
    inference_ms: int,
    image_width: int,
    image_height: int,
    landmarks: list[dict[str, float | None]],
) -> str:
    payload: dict[str, Any] = {
        "frameId": frame.frame_id,
        "timestamp": frame.timestamp_ms,
        "inferenceMs": inference_ms,
        "imageWidth": image_width,
        "imageHeight": image_height,
        "landmarks": landmarks,
    }
    return json.dumps(payload, separators=(",", ":"), allow_nan=False)
