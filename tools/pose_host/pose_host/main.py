from __future__ import annotations

import argparse
import asyncio
import itertools
import logging
import sys
import threading
import time
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

import cv2
import numpy as np
from websockets.asyncio.server import ServerConnection, serve
from websockets.exceptions import ConnectionClosed

from .protocol import encode_packet

LOGGER = logging.getLogger("pose_host")


@dataclass(frozen=True)
class CapturedFrame:
    captured_at_ms: int
    image: np.ndarray


@dataclass(frozen=True)
class StreamConfig:
    camera_index: int = 0
    target_fps: int = 15
    preview_width: int = 360
    preview_height: int = 480
    jpeg_quality: int = 55
    mirror: bool = True


class CameraSource(Protocol):
    def take_latest(self, timeout_seconds: float) -> CapturedFrame | None: ...

    def close(self) -> None: ...


class CameraOpenError(RuntimeError):
    pass


class LatestFrameSlot:
    def __init__(self) -> None:
        self._condition = threading.Condition()
        self._latest: CapturedFrame | None = None
        self._closed = False
        self.dropped = 0

    def put(self, frame: CapturedFrame) -> None:
        with self._condition:
            if self._closed:
                return
            if self._latest is not None:
                self.dropped += 1
            self._latest = frame
            self._condition.notify()

    def take(self, timeout_seconds: float) -> CapturedFrame | None:
        with self._condition:
            self._condition.wait_for(
                lambda: self._latest is not None or self._closed,
                timeout=timeout_seconds,
            )
            frame, self._latest = self._latest, None
            return frame

    def close(self) -> None:
        with self._condition:
            self._closed = True
            self._condition.notify_all()


class StreamPerformance:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._capture_times: deque[float] = deque(maxlen=300)
        self._inference_times: deque[float] = deque(maxlen=300)
        self._send_times: deque[float] = deque(maxlen=300)
        self._inference_ms: deque[int] = deque(maxlen=300)
        self._dropped_capture_frames = 0
        self._last_log_at = 0.0

    def capture(self, *, dropped: bool) -> None:
        with self._lock:
            self._capture_times.append(time.monotonic())
            if dropped:
                self._dropped_capture_frames += 1

    def inference(self, duration_ms: int) -> None:
        with self._lock:
            self._inference_times.append(time.monotonic())
            self._inference_ms.append(duration_ms)

    def sent(self) -> None:
        with self._lock:
            self._send_times.append(time.monotonic())

    def log_if_due(self) -> None:
        with self._lock:
            now = time.monotonic()
            if now - self._last_log_at < 5.0:
                return
            self._last_log_at = now
            LOGGER.info(
                "captureFps=%.1f inferenceFps=%.1f sendFps=%.1f "
                "inferenceP95Ms=%s droppedCapture=%d",
                _fps(self._capture_times),
                _fps(self._inference_times),
                _fps(self._send_times),
                _p95(self._inference_ms),
                self._dropped_capture_frames,
            )


class LatestCamera:
    def __init__(
        self,
        camera_index: int,
        performance: StreamPerformance,
    ) -> None:
        backend = cv2.CAP_AVFOUNDATION if sys.platform == "darwin" else cv2.CAP_ANY
        capture = cv2.VideoCapture(camera_index, backend)
        if not capture.isOpened() and backend != cv2.CAP_ANY:
            capture.release()
            capture = cv2.VideoCapture(camera_index)
        if not capture.isOpened():
            capture.release()
            raise CameraOpenError(f"camera {camera_index} could not be opened")
        capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        self._capture = capture
        self._performance = performance
        self._slot = LatestFrameSlot()
        self._closed = False
        self._thread = threading.Thread(
            target=self._capture_loop,
            name="pose-host-camera",
            daemon=True,
        )
        self._thread.start()

    def _capture_loop(self) -> None:
        while True:
            if self._closed:
                return
            ok, image = self._capture.read()
            if not ok:
                LOGGER.error("camera frame capture failed")
                time.sleep(0.1)
                continue
            frame = CapturedFrame(time.monotonic_ns() // 1_000_000, image)
            before = self._slot.dropped
            self._slot.put(frame)
            self._performance.capture(dropped=self._slot.dropped > before)

    def take_latest(self, timeout_seconds: float) -> CapturedFrame | None:
        return self._slot.take(timeout_seconds)

    def close(self) -> None:
        self._closed = True
        self._slot.close()
        self._capture.release()
        self._thread.join(timeout=1.0)


def prepare_portrait_frame(
    image: np.ndarray,
    *,
    width: int,
    height: int,
    mirror: bool,
) -> np.ndarray:
    if image.ndim != 3 or image.shape[0] <= 0 or image.shape[1] <= 0:
        raise ValueError("camera frame is empty")
    source_height, source_width = image.shape[:2]
    target_ratio = width / height
    source_ratio = source_width / source_height
    if source_ratio > target_ratio:
        crop_width = max(1, round(source_height * target_ratio))
        left = (source_width - crop_width) // 2
        cropped = image[:, left : left + crop_width]
    else:
        crop_height = max(1, round(source_width / target_ratio))
        top = (source_height - crop_height) // 2
        cropped = image[top : top + crop_height, :]
    resized = cv2.resize(cropped, (width, height), interpolation=cv2.INTER_AREA)
    if mirror:
        resized = cv2.flip(resized, 1)
    return np.ascontiguousarray(resized)


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

    def infer(self, image: np.ndarray) -> list[dict[str, float | None]]:
        rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        result = self._landmarker.detect(
            self._mp.Image(image_format=self._mp.ImageFormat.SRGB, data=rgb)
        )
        landmarks = result.pose_landmarks[0] if result.pose_landmarks else []
        return [
            {
                "x": float(item.x),
                "y": float(item.y),
                "z": float(item.z),
                "visibility": float(item.visibility),
                "presence": float(item.presence),
            }
            for item in landmarks
        ]

    def close(self) -> None:
        self._landmarker.close()


class PoseHostServer:
    def __init__(
        self,
        inferencer: MediaPipePoseInferencer,
        config: StreamConfig,
        *,
        camera_factory=None,
    ) -> None:
        self._inferencer = inferencer
        self._config = config
        self._performance = StreamPerformance()
        self._camera_factory = camera_factory or self._open_camera
        self._client_lock = asyncio.Lock()
        self._frame_ids = itertools.count(1)

    def _open_camera(self) -> CameraSource:
        return LatestCamera(self._config.camera_index, self._performance)

    async def handle(self, websocket: ServerConnection) -> None:
        if self._client_lock.locked():
            await websocket.close(1013, "single client only")
            return
        async with self._client_lock:
            try:
                camera = self._camera_factory()
            except CameraOpenError as error:
                LOGGER.error("camera open failure: %s", error)
                await websocket.close(1011, "camera open failure")
                return
            LOGGER.info("client connected")
            try:
                await self._stream(websocket, camera)
            except (ConnectionClosed, ConnectionError):
                pass
            finally:
                camera.close()
                LOGGER.info("client disconnected")

    async def _stream(
        self,
        websocket: ServerConnection,
        camera: CameraSource,
    ) -> None:
        minimum_interval = 1.0 / self._config.target_fps
        last_started = 0.0
        while True:
            delay = minimum_interval - (time.monotonic() - last_started)
            if delay > 0:
                await asyncio.sleep(delay)
            captured = await asyncio.to_thread(camera.take_latest, 0.5)
            if captured is None:
                continue
            last_started = time.monotonic()
            packet = await asyncio.to_thread(self._process, captured)
            await websocket.send(packet)
            self._performance.sent()
            self._performance.log_if_due()

    def _process(self, captured: CapturedFrame) -> bytes:
        frame = prepare_portrait_frame(
            captured.image,
            width=self._config.preview_width,
            height=self._config.preview_height,
            mirror=self._config.mirror,
        )
        started = time.perf_counter()
        landmarks = self._inferencer.infer(frame)
        inference_ms = round((time.perf_counter() - started) * 1000)
        self._performance.inference(inference_ms)
        ok, encoded = cv2.imencode(
            ".jpg",
            frame,
            [cv2.IMWRITE_JPEG_QUALITY, self._config.jpeg_quality],
        )
        if not ok:
            raise RuntimeError("JPEG encoding failed")
        return encode_packet(
            frame_id=next(self._frame_ids),
            captured_at_ms=captured.captured_at_ms,
            image_width=self._config.preview_width,
            image_height=self._config.preview_height,
            inference_ms=inference_ms,
            landmarks=landmarks,
            jpeg=encoded.tobytes(),
        )


def _fps(values: deque[float]) -> float:
    if len(values) < 2:
        return 0.0
    elapsed = values[-1] - values[0]
    return (len(values) - 1) / elapsed if elapsed > 0 else 0.0


def _p95(values: deque[int]) -> int | str:
    if not values:
        return "-"
    ordered = sorted(values)
    return ordered[round((len(ordered) - 1) * 0.95)]


def default_model_path() -> Path:
    return (
        Path(__file__).resolve().parents[3]
        / "android/app/src/main/assets/pose_landmarker_lite.task"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="MICHIZURE host Pose server")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--target-fps", type=int, default=15)
    parser.add_argument("--preview-width", type=int, default=360)
    parser.add_argument("--preview-height", type=int, default=480)
    parser.add_argument("--jpeg-quality", type=int, default=55)
    parser.add_argument("--mirror", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--model", type=Path, default=default_model_path())
    return parser.parse_args()


async def run(args: argparse.Namespace) -> None:
    config = StreamConfig(
        camera_index=args.camera,
        target_fps=args.target_fps,
        preview_width=args.preview_width,
        preview_height=args.preview_height,
        jpeg_quality=args.jpeg_quality,
        mirror=args.mirror,
    )
    inferencer = MediaPipePoseInferencer(args.model)
    server = PoseHostServer(inferencer, config)
    try:
        async with serve(server.handle, "0.0.0.0", args.port, max_size=1_024):
            LOGGER.info("listening on 0.0.0.0:%d", args.port)
            await asyncio.get_running_loop().create_future()
    finally:
        inferencer.close()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    args = parse_args()
    if not 1 <= args.target_fps <= 15:
        raise SystemExit("--target-fps must be between 1 and 15")
    if args.preview_width <= 0 or args.preview_height <= 0:
        raise SystemExit("preview dimensions must be positive")
    if not 1 <= args.jpeg_quality <= 100:
        raise SystemExit("--jpeg-quality must be between 1 and 100")
    try:
        asyncio.run(run(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
