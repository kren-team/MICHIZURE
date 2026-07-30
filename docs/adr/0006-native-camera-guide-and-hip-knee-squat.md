# ADR 0006: Native Camera guideとhip/knee bandで部分画角のスクワットを判定する

- Status: Accepted
- Date: 2026-07-31
- Amends: [ADR 0005](0005-mediapipe-pose-landmarker.md) のoverlay、quality gate、feature部分

## Context

最終デモのhost webcam確認で、FlutterのguideとNative `PreviewView`が異なるboundsとscaleで描かれ、映像、黒帯、空白、guideがずれた。また、ADR 0005のhip / knee / ankle、knee angle、velocityを必須にする判定は「みぞおちから膝下」の部分画角でankleを安定取得できず、立位calibrationへ進めなかった。

Camera frameやlandmarkをFlutterへ高頻度転送せず、既存のMediaPipe Lite、One-Euro Filter、時系列FSM、Contribution冪等性を維持したまま、実Cameraで説明可能な最小判定へ収束させる必要がある。

## Decision

### Preview / guide

- Flutterはportrait 3:4の`AndroidView`を1つだけ表示する。
- Nativeは1つの`SquatCameraContainer : FrameLayout`にmatch-parentの`PreviewView`と`SquatGuideOverlayView`を重ねる。
- `PreviewView`は`FIT_CENTER`と`COMPATIBLE`を使う。CameraXは`COMPATIBLE`でなければ`getOutputTransform()`がView matrixを反映しない可能性がある。
- PreviewとImageAnalysisを同じ`ViewPort`の`UseCaseGroup`へbindする。
- Analysis座標のhip / knee点は`ImageProxyTransformFactory`と`CoordinateTransform`でPreview座標へ写す。front camera mirrorは表示変換だけへ適用し、MediaPipeの解剖学的left/rightを入れ替えない。
- Native guideはhip / knee bandとtracking / FSM stateだけを最大10 FPSで描く。座標はFlutterへ送らない。

### Quality / feature

- 同じ側のhip / kneeが両方validならState Machineへ入力できる。ankle、face、shoulder、full-body heightは必須にしない。
- `no pose`、`hip unavailable`、`knee unavailable`、`confidence insufficient`、`valid`を別状態にする。
- calibrationでstanding hip yとstanding hip-to-knee vertical gapのmedianを保存する。
- 各frameは次を計算する。

```text
gapRatio = (currentKneeY - currentHipY) / standingGap
hipDrop = (currentHipY - baselineHipY) / standingGap
```

- BOTTOM候補は`gapRatio <= 0.30`かつ`hipDrop >= 0.35`とする。STANDING候補は`gapRatio >= 0.75`かつ`hipDrop <= 0.15`とする。
- thresholdは`SquatDetectorConfig`へ集約し、stable duration、hysteresis、minimum duration、ROM、refractory、pose-loss resetを維持する。
- knee angle、angular velocity、hip velocityはProduction必須条件から外す。実測で必要性が確認されるまで再追加しない。

## Consequences

- みぞおちから膝下までの画角でankleが欠けても判定経路へ入れる。
- gapだけ縮む動作とhipだけ下がる前屈をAND条件で除外できるが、2Dのhip / knee軌跡が同じ別動作を完全には区別できない。
- Previewとguideは同じboundsとCameraX transformを共有し、Flutter rebuildから独立する。
- MediaPipe model、Camera permission、Firestore schema / Rules / Index、Contribution event identityは変更しない。
- 実人体でのprecision、浅い屈伸reject、Preview滑らかさはhost webcamまたは物理端末のmanual gateで判定し、自動testだけで達成済みとしない。

## References

- [PreviewView](https://developer.android.com/reference/androidx/camera/view/PreviewView)
- [ImageProxyTransformFactory](https://developer.android.com/reference/androidx/camera/view/transform/ImageProxyTransformFactory)
- [CoordinateTransform](https://developer.android.com/reference/androidx/camera/view/transform/CoordinateTransform)
- [CameraX coordinate transform](https://developer.android.com/media/camera/camerax/transform-output)
