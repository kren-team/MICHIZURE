#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "エラー: ${BASH_SOURCE[0]}:${LINENO} で失敗しました。" >&2' ERR

PACKAGE_NAME="${PACKAGE_NAME:-com.kren.michizure}"
DEFINES_FILE="${DEFINES_FILE:-.dart_defines/firebase-demo.json}"
APK_PATH="${APK_PATH:-build/app/outputs/flutter-apk/app-profile.apk}"
POSE_PORT="${POSE_PORT:-8765}"
RENDER_HEALTH_URL="${RENDER_HEALTH_URL:-https://michizure.onrender.com/health}"
RESET_APP_DATA=0
SKIP_BUILD=0
SKIP_POSE=0
DEVICE_ID="${DEVICE_ID:-}"

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'USAGE'
使い方:
  ./scripts/demo/setup_one_device.sh
  ./scripts/demo/setup_one_device.sh --reset
  ./scripts/demo/setup_one_device.sh --device emulator-5554
  ./scripts/demo/setup_one_device.sh --skip-build
  ./scripts/demo/setup_one_device.sh --no-pose

オプション:
  --reset            アプリを削除してログイン状態も初期化する
  --device ID        使用する端末IDを指定する
  --skip-build       既存のProfile APKを使用する
  --no-pose          Pose Serverを起動しない
  -h, --help         ヘルプを表示する
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "必要なコマンドが見つかりません: $1" >&2
    exit 1
  fi
}

check_requirements() {
  require_command adb
  require_command flutter
  require_command uv
  require_command curl
  require_command lsof

  if [[ ! -f "$DEFINES_FILE" ]]; then
    echo "設定ファイルが見つかりません: $DEFINES_FILE" >&2
    exit 1
  fi

  if command -v jq >/dev/null 2>&1; then
    local pose_source
    pose_source="$(jq -r '.POSE_SOURCE // empty' "$DEFINES_FILE")"
    if [[ "$pose_source" != "host" ]]; then
      echo "警告: $DEFINES_FILE の POSE_SOURCE が host ではありません: ${pose_source:-未設定}" >&2
    fi
  else
    echo "警告: jq がないためPOSE_SOURCEの確認を省略します。"
  fi
}

check_render() {
  echo "Renderの稼働確認: $RENDER_HEALTH_URL"
  if curl --fail --silent --show-error --max-time 30 "$RENDER_HEALTH_URL" >/dev/null; then
    echo "Render: OK"
  else
    echo "警告: Renderのhealth確認に失敗しました。通知テスト前に確認してください。" >&2
  fi
}

start_pose_server() {
  if lsof -nP -iTCP:"$POSE_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Pose Server: 既にポート $POSE_PORT で起動しています。"
    return
  fi

  mkdir -p .run .logs
  echo "Pose Serverをバックグラウンド起動します。"

  nohup uv run --project tools/pose_host \
    python -m pose_host.main \
    --port "$POSE_PORT" \
    --camera 0 \
    --target-fps 15 \
    --preview-width 360 \
    --preview-height 480 \
    --jpeg-quality 55 \
    --mirror \
    > .logs/pose_host.log 2>&1 &

  local pose_pid=$!
  echo "$pose_pid" > .run/pose_host.pid

  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if lsof -nP -iTCP:"$POSE_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "Pose Server: OK (PID=$pose_pid, log=.logs/pose_host.log)"
      return
    fi
    sleep 0.5
  done

  echo "Pose Serverが起動しませんでした。ログ:" >&2
  tail -n 50 .logs/pose_host.log >&2 || true
  exit 1
}

build_apk() {
  echo "Profile APKをビルドします。"
  flutter build apk --profile \
    --dart-define-from-file="$DEFINES_FILE"

  if [[ ! -f "$APK_PATH" ]]; then
    echo "APKが生成されませんでした: $APK_PATH" >&2
    exit 1
  fi
}

install_and_launch() {
  local device_id="$1"

  if [[ "$RESET_APP_DATA" == "1" ]]; then
    echo "[$device_id] 既存アプリを削除して初期化します。"
    adb -s "$device_id" uninstall "$PACKAGE_NAME" >/dev/null 2>&1 || true
    adb -s "$device_id" install "$APK_PATH"
  else
    echo "[$device_id] ログイン状態を保持して上書きインストールします。"
    adb -s "$device_id" install -r "$APK_PATH"
  fi

  adb -s "$device_id" logcat -c || true
  adb -s "$device_id" shell monkey \
    -p "$PACKAGE_NAME" \
    -c android.intent.category.LAUNCHER 1 \
    >/dev/null

  echo "[$device_id] 起動完了"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset)
      RESET_APP_DATA=1
      shift
      ;;
    --device)
      DEVICE_ID="${2:-}"
      [[ -n "$DEVICE_ID" ]] || { echo "--device の後に端末IDが必要です。" >&2; exit 1; }
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --no-pose)
      SKIP_POSE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "不明なオプション: $1" >&2
      usage
      exit 1
      ;;
  esac
done

check_requirements

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(adb devices | awk '$2=="device" && $1 ~ /^emulator-/ {print $1; exit}')"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "起動中のAndroid Emulatorが見つかりません。" >&2
  adb devices
  exit 1
fi

echo "使用端末: $DEVICE_ID"
check_render

if [[ "$SKIP_POSE" == "0" ]]; then
  start_pose_server
fi

if [[ "$SKIP_BUILD" == "0" ]]; then
  build_apk
elif [[ ! -f "$APK_PATH" ]]; then
  echo "--skip-build が指定されましたがAPKがありません: $APK_PATH" >&2
  exit 1
fi

install_and_launch "$DEVICE_ID"

cat <<EOF2

1台セットアップ完了
  Device: $DEVICE_ID
  APK:    $APK_PATH
  Reset:  $RESET_APP_DATA

ログ確認:
  adb -s "$DEVICE_ID" logcat | grep --line-buffered -E \
    'FirebaseMessaging|FLTFire|Firestore|PERMISSION_DENIED|Unhandled|Bad state|HostPose|SquatRep'
EOF2
