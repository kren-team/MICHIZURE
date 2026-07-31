from __future__ import annotations

import argparse
import asyncio
import io
import logging
import time
from collections.abc import Callable
from pathlib import Path
import numpy as np
from PIL import Image
from websockets.asyncio.server import ServerConnection, serve

from .protocol import FrameMessage, decode_frame, encode_result

LOGGER = logging.getLogger("pose_host")


class LatestFrameSlot:
    def __init__(self) -> None:
        self._condition = asyncio.Condition()
        self._pending: FrameMessage | None = None
        self._closed = False
        self.dropped = 0

    async def put(self, frame: FrameMessage) -> None:
        async with self._condition:
            if self._pending is not None:
                self.dropped += 1
            self._pending = frame
            self._condition.notify()

    async def take(self) -> FrameMessage | None:
        async with self._condition:
            await self._condition.wait_for(
                lambda: self._pending is not None or self._closed
            )
            frame, self._pending = self._pending, None
            return frame

    async def close(self) -> None:
        async with self._condition:
            self._closed = True
            self._condition.notify_all()


class MediaPipePoseInferencer:
    def __init__(self, model_path: Path) -> None:
        import mediapipe as mp
        from mediapipe.tasks import python
        from mediapipe.tasks.python import vision

        options = vision.PoseLandmarkerOptions(
            base_options=python.BaseOptions(model_asset_path=str(model_path)),
            running_mode=vision.RunningMode.IMAGE,
            num_poses=1,
            output_segmentation_masks=False,
            min_pose_detection_confidence=0.5,
            min_pose_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        self._mp = mp
        self._landmarker = vision.PoseLandmarker.create_from_options(options)

    def infer(
        self, frame: FrameMessage
    ) -> tuple[int, int, list[dict[str, float | None]]]:
        with Image.open(io.BytesIO(frame.jpeg)) as source:
            image = source.convert("RGB")
            if frame.rotation_degrees:
                image = image.rotate(-frame.rotation_degrees, expand=True)
            pixels = np.asarray(image)
        mp_image = self._mp.Image(
            image_format=self._mp.ImageFormat.SRGB,
            data=pixels,
        )
        result = self._landmarker.detect(mp_image)
        landmarks = result.pose_landmarks[0] if result.pose_landmarks else []
        values = [
            {
                "x": float(item.x),
                "y": float(item.y),
                "z": float(item.z),
                "visibility": float(item.visibility),
                "presence": float(item.presence),
            }
            for item in landmarks
        ]
        return image.width, image.height, values

    def close(self) -> None:
        self._landmarker.close()


class PoseHostServer:
    def __init__(
        self,
        infer: Callable[
            [FrameMessage], tuple[int, int, list[dict[str, float | None]]]
        ],
        target_fps: int,
    ) -> None:
        self._infer = infer
        self._minimum_interval = 1.0 / target_fps
        self._client_lock = asyncio.Lock()

    async def handle(self, websocket: ServerConnection) -> None:
        if self._client_lock.locked():
            await websocket.close(1013, "single client only")
            return
        async with self._client_lock:
            LOGGER.info("client connected")
            slot = LatestFrameSlot()
            worker = asyncio.create_task(self._worker(websocket, slot))
            try:
                async for message in websocket:
                    if not isinstance(message, bytes):
                        continue
                    try:
                        await slot.put(decode_frame(message))
                    except ValueError as error:
                        LOGGER.warning("invalid frame: %s", error)
            finally:
                await slot.close()
                worker.cancel()
                await asyncio.gather(worker, return_exceptions=True)
                LOGGER.info("client disconnected; dropped=%d", slot.dropped)

    async def _worker(
        self, websocket: ServerConnection, slot: LatestFrameSlot
    ) -> None:
        last_started = 0.0
        while True:
            frame = await slot.take()
            if frame is None:
                return
            delay = self._minimum_interval - (time.monotonic() - last_started)
            if delay > 0:
                await asyncio.sleep(delay)
            last_started = time.monotonic()
            started = time.perf_counter()
            try:
                width, height, landmarks = await asyncio.to_thread(self._infer, frame)
            except Exception:
                LOGGER.exception("Pose inference failed")
                await websocket.close(1011, "Pose inference failed")
                return
            inference_ms = round((time.perf_counter() - started) * 1000)
            await websocket.send(
                encode_result(
                    frame,
                    inference_ms=inference_ms,
                    image_width=width,
                    image_height=height,
                    landmarks=landmarks,
                )
            )


def default_model_path() -> Path:
    return (
        Path(__file__).resolve().parents[3]
        / "android/app/src/main/assets/pose_landmarker_lite.task"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="MICHIZURE host Pose server")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--target-fps", type=int, default=12)
    parser.add_argument("--model", type=Path, default=default_model_path())
    return parser.parse_args()


async def run(args: argparse.Namespace) -> None:
    inferencer = MediaPipePoseInferencer(args.model)
    server = PoseHostServer(inferencer.infer, args.target_fps)
    try:
        async with serve(server.handle, "0.0.0.0", args.port, max_size=2_000_000):
            LOGGER.info("listening on 0.0.0.0:%d", args.port)
            await asyncio.get_running_loop().create_future()
    finally:
        inferencer.close()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    args = parse_args()
    if args.target_fps <= 0:
        raise SystemExit("--target-fps must be positive")
    try:
        asyncio.run(run(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
