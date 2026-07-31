# ADR 0007: 膝角度と正規化した腰下降量でスクワットを判定する

- Status: Accepted
- Date: 2026-07-31
- Supersedes: [ADR 0005](0005-mediapipe-pose-landmarker.md) の解析FPS、画面ガイド、FSM入力条件

## Context

MediaPipe移行後も、Camera PreviewとFlutter製ガイドが別のboundsで描画され、実Cameraでは映像と案内が一致しなかった。またFSMが膝角度と腰下降量に加えてframe間速度を必須にしていたため、8〜12 FPSの揺らぎやOne-Euro Filterの影響で正常な下降・上昇が開始条件を満たしにくかった。

## Decision

- Native `FrameLayout`内へ`PreviewView`と`SquatGuideOverlayView`を同じ`MATCH_PARENT` boundsで重ねる。Flutterはportrait 3:4のAndroidViewを1つだけ保持する。
- `PreviewView.ImplementationMode.COMPATIBLE`と`FIT_CENTER`を使用し、CameraX `OutputTransform` / `CoordinateTransform`でImageAnalysis座標をPreview座標へ変換する。
- Previewは24〜30 FPSをrequestし、ImageAnalysisはGPU 12 FPS、CPU fallback 8 FPSへ画像変換前にthrottleする。backpressureは`KEEP_ONLY_LATEST`、in-flightは1件とする。
- quality gateとside選択は、同一側のhip / knee / ankleを必須にする。顔、肩、腕は要求しない。
- calibrationは1秒間の複数sampleからstanding knee angle、hip Y、leg scaleをmedianで得る。
- Production FSMの判定入力はknee angleとnormalized hip dropの2つに限定する。速度はdebug診断に残すがtransition条件にはしない。
- `CALIBRATING → STANDING → DESCENDING → BOTTOM → ASCENDING → STANDING`を順に通り、depth、ROM、各phase時間、valid frame率、return-to-standing、refractoryをすべて満たした場合だけ1 repにする。
- knee angle 55°以下かつhip drop 0.20以上の過深動作は警告してrejectする。
- debug buildだけ、FirebaseやDebtを使わないSquat Labをrouteへ追加する。release routeでは`kDebugMode`により除外する。

## Consequences

- 解析速度の揺らぎがdirection判定を妨げず、状態遷移はframe値と経過時間で説明できる。
- 2D knee angleは撮影角度に依存するため、胸の下から足首を映し、斜め30〜45度または横向きを案内する。
- Camera frame、landmark、座標履歴はFlutter、Firestore、logへ送らない。Native overlayへは現在frameの選択側3点だけを最大10 FPSで渡し、描画後に保持しない。
- 閾値と物理端末性能は実人体manual gateで確認する。synthetic testだけで精度・latency達成を主張しない。

## References

- [CameraX transform output](https://developer.android.com/media/camera/camerax/transform-output)
- [CameraX PreviewView](https://developer.android.com/reference/androidx/camera/view/PreviewView)
- [MediaPipe Pose Landmarker Android](https://developers.google.com/mediapipe/solutions/vision/pose_landmarker/android)
- [参考: 3点から膝角度を計算する考え方](https://qiita.com/SSS-MingXianwen/items/8e4075fac88c5b6d3888)
