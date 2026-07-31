# Emulator + Host Pose demo

1. Hardware graphicsでEmulatorを起動する。

   発表用AVDはGraphicsをHardwareまたはAutomatic、CPUを4 core以上、RAMを4096MB以上にする。

   ```bash
   emulator -avd Pixel_8 -gpu host
   ```

2. Terminal 1でFirebase Emulatorを起動する。

   ```bash
   firebase emulators:start
   ```

3. Terminal 2でPC側Pose serverを起動する。serverがPC Webカメラを直接開き、同じportrait画像で推論とpreview配信を行う。

   ```bash
   uv run --project tools/pose_host python -m pose_host.main \
     --port 8765 \
     --camera 0 \
     --target-fps 15 \
     --preview-width 360 \
     --preview-height 480 \
     --jpeg-quality 55 \
     --mirror
   ```

4. Terminal 3でprofile mode、HOST_DEMO、Firebase Emulatorを指定する。

   ```bash
   flutter run --profile \
     --dart-define=POSE_SOURCE=host \
     --dart-define=USE_FIREBASE_EMULATORS=true \
     -d emulator-5554
   ```

画面が `Host Pose: Ready` になるまでrep判定は開始しない。server切断中は最後の画像を消して1秒間隔で再接続する。HOST_DEMOではAndroidのCameraXと端末内Pose推論を起動せず、EmulatorのVirtual Scene CameraやWebcam設定もアプリから使用しない。端末内推論へ戻す場合は`POSE_SOURCE=host`を指定しない。
