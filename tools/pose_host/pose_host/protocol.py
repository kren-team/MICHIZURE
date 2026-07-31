from __future__ import annotations

import json
import struct
from typing import Any

PROTOCOL_VERSION = 1
HEADER_LENGTH = struct.Struct(">I")


def encode_packet(
    *,
    frame_id: int,
    captured_at_ms: int,
    image_width: int,
    image_height: int,
    inference_ms: int,
    landmarks: list[dict[str, float | None]],
    jpeg: bytes,
) -> bytes:
    header: dict[str, Any] = {
        "protocolVersion": PROTOCOL_VERSION,
        "frameId": frame_id,
        "capturedAtMs": captured_at_ms,
        "imageWidth": image_width,
        "imageHeight": image_height,
        "jpegLength": len(jpeg),
        "inferenceMs": inference_ms,
        "poseDetected": bool(landmarks),
        "landmarks": landmarks,
    }
    encoded_header = json.dumps(
        header,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    return HEADER_LENGTH.pack(len(encoded_header)) + encoded_header + jpeg
