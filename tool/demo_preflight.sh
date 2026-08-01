#!/usr/bin/env bash
set -euo pipefail

device_serial="${MICHIZURE_DEVICE_SERIAL:-emulator-5554}"
adb_bin="${MICHIZURE_ADB_BIN:-adb}"
app_id="com.kren.michizure"
target_id="com.kren.michizure.demotarget"
failures=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

check_host_endpoint() {
  local label="$1"
  local url="$2"
  if curl --silent --show-error --max-time 2 --output /dev/null "$url"; then
    pass "$label"
  else
    fail "$label"
  fi
}

check_host_endpoint "Firebase Auth Emulator :9099" "http://127.0.0.1:9099/"
check_host_endpoint "Firestore Emulator :8080" "http://127.0.0.1:8080/"

if ! "$adb_bin" -s "$device_serial" get-state >/dev/null 2>&1; then
  fail "Android Emulator $device_serial"
  exit 1
fi
pass "Android Emulator $device_serial"

if "$adb_bin" -s "$device_serial" shell pm path "$app_id" \
  | grep -q '^package:'; then
  pass "MICHIZURE installed"
else
  fail "MICHIZURE installed"
fi

if "$adb_bin" -s "$device_serial" shell dpm list-owners \
  | grep -q "$app_id/.admin.MichizureDeviceAdminReceiver"; then
  pass "Device Owner"
else
  fail "Device Owner"
fi

if "$adb_bin" -s "$device_serial" shell appops get "$app_id" GET_USAGE_STATS \
  | grep -q 'allow'; then
  pass "Usage Access"
else
  fail "Usage Access"
fi

if "$adb_bin" -s "$device_serial" shell dumpsys package "$app_id" \
  | grep 'android.permission.POST_NOTIFICATIONS:' \
  | grep -q 'granted=true'; then
  pass "Notification permission"
else
  fail "Notification permission"
fi

if "$adb_bin" -s "$device_serial" shell dumpsys user \
  | grep -q 'RUNNING_UNLOCKED'; then
  pass "User unlocked"
else
  fail "User unlocked"
fi

if "$adb_bin" -s "$device_serial" shell pm path "$target_id" \
  | grep -q '^package:'; then
  pass "Demo target installed"
else
  fail "Demo target installed"
fi

if "$adb_bin" -s "$device_serial" shell dumpsys package "$target_id" \
  | grep -q 'suspended=true'; then
  fail "Demo target is currently unsuspended"
else
  pass "Demo target is currently unsuspended"
fi

if [[ "${MICHIZURE_REQUIRE_CAMERA:-0}" == "1" ]]; then
  if "$adb_bin" -s "$device_serial" shell dumpsys package "$app_id" \
    | grep 'android.permission.CAMERA:' \
    | grep -q 'granted=true'; then
    pass "Camera permission"
  else
    fail "Camera permission"
  fi
else
  echo "INFO: Camera permission is checked in the repayment screen."
fi

echo "INFO: Confirm Auth user, Group, selected package count, active Task, Debt, and lock obligation in the app UI."

if ((failures > 0)); then
  echo "Preflight failed: $failures item(s) require action."
  exit 1
fi

echo "Preflight passed."
