# Emulator + Host Pose demo

1. Hardware graphicsでEmulatorを起動する。

   ```bash
   emulator -avd Pixel_8 -gpu host
   ```

2. repository rootでPC側Pose serverを起動する。serverはEmulatorから受信したframeだけを処理する。

   ```bash
   uv run --project tools/pose_host python -m pose_host.main \
     --port 8765 \
     --target-fps 12
   ```

3. 発表用はprofile modeとHOST_DEMOを指定する。

   ```bash
   flutter run --profile \
     --dart-define=POSE_SOURCE=host \
     -d emulator-5554
   ```

画面が `Host Pose: Ready` になるまでrep判定は開始しない。server切断中もCamera Previewは継続し、1秒間隔で再接続する。端末内推論へ戻す場合は`POSE_SOURCE=host`を指定しない。
