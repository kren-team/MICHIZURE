# ADR 0005: MediaPipe Pose Landmarker Liteで低遅延スクワット判定を行う

- Status: Accepted
- Date: 2026-07-30
- Supersedes: [ADR 0004](0004-on-device-pose-detection.md) のProduction pose SDK部分
- Amended by: [ADR 0006](0006-native-camera-guide-and-hip-knee-squat.md) のoverlay、quality gate、feature部分

## Context

実Cameraの最終確認で、ML Kit Pose DetectionへCameraXの利用可能frameを明示的なFPS制限なしで投入し、5 sample medianとEMAを重ねた構成では、previewを含む端末操作が重く、lower-body入力から状態機械が実用的に進まなかった。debug diagnosticsも同じRiverpod stateへ最大5 FPSで入り、返済画面全体を再buildしていた。

Camera frameやlandmarkを外部へ出さず、Previewを解析backlogから分離し、1 repごとの低遅延eventだけを既存Contributionへ渡す必要がある。

## Decision

- CameraX `Preview`と`ImageAnalysis`を別use caseにする。
- Previewはcameraの通常frame rate（目標30 FPS）を妨げず、AnalysisはRGBA 480×640近傍、`STRATEGY_KEEP_ONLY_LATEST`にする。
- Production pose SDKは`com.google.mediapipe:tasks-vision:1.0.0`へ固定する。AARのmanifest要件に合わせ、appのminSdkは24以上とする。
- Google AI Edge公式Pose Landmarker Lite bundleを`pose_landmarker_lite.task`としてassetへ同梱する。runtime downloadは行わない。
- `RunningMode.LIVE_STREAM`、`numPoses=1`、segmentation maskなし、GPU優先・CPU fallbackを使用する。
- GPUでは15 FPS、CPU fallbackでは10 FPSへ、重いBitmap copy前にthrottleする。推論中frameはqueueせず捨てる。
- MediaPipeの33 landmarksはadapter内で`LowerBodyPose`へ縮約し、Flutterへ送らない。ADR 0006以降のqualityは同じ側のhip / kneeを必須、ankleを任意とする。
- 解剖学的なleft/rightを内部定義とし、front camera previewのmirrorを推論入力へ適用しない。ADR 0006のnative hip / knee bandだけをCameraX transformでviewer座標へ変換する。
- 左右別のOne-Euro Filterをlandmark座標へ適用する。ADR 0006以降のProduction featureはstanding hip/knee gapで正規化したgap ratioとhip dropであり、FSMの二重平滑化は行わない。
- rep、guidance変化、debug diagnosticsを別eventとして扱う。diagnosticsはdebug buildだけ、最大5 FPSで、小さい専用Widgetだけを更新する。
- GPUとCPUの両方が初期化不能ならtyped native errorにする。

## Model artifact

| 項目 | 値 |
|---|---|
| Model | MediaPipe Pose Landmarker Lite, float16 task bundle |
| Source | `https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task` |
| GCS generation | `1682624738331272` |
| Size | `5,777,746 bytes` |
| SHA-256 | `59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a` |
| License | Apache License 2.0（公式BlazePose GHUM 3D model card） |
| Runtime download | なし |

公式model cardはhead非表示をout-of-scopeとし、full-body cropを推奨している。したがって、みぞおち〜膝下の部分画角での実Camera成立率は自動testから推測せず、host webcam / 物理端末のmanual gateで計測する。adapterとquality gateは顔・肩・足首を必須にしないが、modelがpose自体を返さない場合まで成功扱いにはしない。

## Image ownership

1. CameraXはRGBA `ImageProxy`をanalyzerへ渡す。
2. throttle / busyならその場で`ImageProxy.close()`する。
3. accepted frameはRGBAをARGB Bitmapへ1回copyし、rotationを適用する。JPEG encode/decodeはしない。
4. copy完了後、analyzerの`finally`で`ImageProxy`をcloseする。
5. `BitmapImageBuilder`のMPImageとBitmapはpending 1件だけ保持する。
6. MediaPipe result / error / stopの各pathでMPImageとBitmapをexactly onceでreleaseする。

GPU taskは生成した専用single threadから`detectAsync`し、instanceをframeごとに作らない。

## Firestore compatibility

Contribution schema / Security Rulesは今回変更しない。既存field `detectorType`はRulesで`mlkit`に固定されているため、Firestore writeでは後方互換値を維持し、実際のengineとversionは`detectorVersion=mediapipe-lite-hip-knee-v4`で識別する。Native→Flutter contractでは`detectorType=mediapipe`を検証する。このlegacy fieldはserver-side detector attestationではなく、既存MVP trust boundaryである。

## Consequences

- ML Kit Pose dependencyとadapterはreleaseから削除される。
- Lite model 1 bundleとMediaPipe native librariesによりAPK sizeは変化する。
- CPU fallbackはPreviewを止めず、解析を10 FPSに落とす。
- Camera frame、landmark、world landmark、座標履歴は保存・送信しない。
- MediaPipeのmodel性能とGPU availabilityは端末依存であり、Emulator測定を物理端末SLAとして扱わない。

## References

- [Pose landmark detection guide for Android](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/android)
- [Pose Landmarker overview and models](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/index)
- [BlazePose GHUM 3D model card](https://storage.googleapis.com/mediapipe-assets/Model%20Card%20BlazePose%20GHUM%203D.pdf)
- [Google Maven metadata: tasks-vision](https://dl.google.com/dl/android/maven2/com/google/mediapipe/tasks-vision/maven-metadata.xml)
- [CameraX ImageAnalysis](https://developer.android.com/media/camera/camerax/analyze)
