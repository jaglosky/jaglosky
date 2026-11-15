#!/usr/bin/env bash
# Emulator smoke test: install → launch → back gesture → rotation → logcat crash gate.
# Does not stop at the first error — collects evidence and writes the result to $OUT/result.txt.
set -uo pipefail
APK="$1"
PKG="$2"
OUT="$3"
mkdir -p "$OUT"
: > "$OUT/notes.txt"
result=pass
note() { echo "$1" >> "$OUT/notes.txt"; echo "• $1"; }
# An overloaded CI emulator can show the system "System UI isn't responding" dialog — close
# dialogs before each screenshot (app crashes are caught from logcat anyway, not from dialogs).
calm() { adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null 2>&1 || true; }
shot() { calm; sleep 1; adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null || note "could not take screenshot $1"; }

# APK: a file, or a directory (artifact) with the build — release (Expo/RN) or debug (native, Flutter).
# `app-base.apk` next to it = the same app BEFORE the change (base branch) — for the before / after screenshots.
BASE_APK=""
if [ -d "$APK" ]; then
  [ -f "$APK/app-base.apk" ] && BASE_APK="$APK/app-base.apk"
  APK="$(ls "$APK"/*.apk 2>/dev/null | grep -v '/app-base\.apk$' | head -1)"
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$APK" ] || [ ! -f "$APK" ]; then
  note "no APK to test"
  echo fail > "$OUT/result.txt"
  exit 0
fi
# Package: from the input, otherwise from the APK manifest (aapt2/aapt from the newest build-tools).
if [ -z "$PKG" ]; then
  SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  AAPT="$(ls -d "$SDK"/build-tools/*/aapt2 "$SDK"/build-tools/*/aapt 2>/dev/null | sort -V | tail -1)"
  [ -n "$AAPT" ] && PKG="$("$AAPT" dump badging "$APK" 2>/dev/null | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)"
  if [ -z "$PKG" ]; then
    note "could not read the package name from the APK (set the package input)"
    echo fail > "$OUT/result.txt"
    exit 0
  fi
fi
echo "APK: $(basename "$APK") · package: $PKG"

adb wait-for-device
echo "Android: $(adb shell getprop ro.build.version.release | tr -d '\r') (API $(adb shell getprop ro.build.version.sdk | tr -d '\r'))" | tee "$OUT/device.txt"
# No system ANR/crash dialogs (they cover screenshots); give the emulator a moment to settle after boot.
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
sleep 20
calm

# 0. Before the change: the base build's launch screen (same emulator, same wait), then a clean uninstall.
if [ -n "$BASE_APK" ]; then
  if adb install -r "$BASE_APK" > "$OUT/install-base.log" 2>&1; then
    adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
    sleep 45
    shot 00-before-this-change
  else
    note "could not install the base build — no before / after comparison"
    BASE_APK=""
  fi
  adb uninstall "$PKG" > /dev/null 2>&1 || true
fi

if ! adb install -r "$APK" > "$OUT/install.log" 2>&1; then
  note "APK installation failed (install.log)"
  echo fail > "$OUT/result.txt"
  exit 0
fi
adb logcat -c

# 1. Cold start (RN + Hermes on an emulator without a GPU needs a moment) — recorded for the PR.
adb shell screenrecord --time-limit 30 --size 540x1200 --bit-rate 2000000 /sdcard/jaglosky-launch.mp4 > /dev/null 2>&1 &
RECORDER=$!
sleep 2
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
sleep 45
shot 01-launch
wait "$RECORDER" 2>/dev/null || true
if adb pull /sdcard/jaglosky-launch.mp4 "$OUT/launch.mp4" > /dev/null 2>&1 && [ -s "$OUT/launch.mp4" ]; then
  # A GIF plays inline in the PR comment; without ffmpeg the comment links the video.
  command -v ffmpeg > /dev/null 2>&1 || timeout 120 sudo apt-get install -y -qq ffmpeg > /dev/null 2>&1 || true
  if command -v ffmpeg > /dev/null 2>&1; then
    ffmpeg -y -loglevel error -i "$OUT/launch.mp4" -vf "fps=5,scale=270:-1:flags=lanczos" "$OUT/launch.gif" 2>/dev/null || rm -f "$OUT/launch.gif"
  fi
else
  rm -f "$OUT/launch.mp4"
fi
# Before / after: the launch screens compared pixel by pixel (status bar ignored). Information, never a failure —
# content loaded from the network can differ between two launches.
if [ -n "$BASE_APK" ] && [ -s "$OUT/00-before-this-change.png" ] && [ -s "$OUT/01-launch.png" ]; then
  PCT="$(python3 -I "$HERE/imgdiff.py" "$OUT/00-before-this-change.png" "$OUT/01-launch.png" "$OUT/01b-difference.png" 2>/dev/null || true)"
  if [ -n "$PCT" ]; then
    echo "$PCT" > "$OUT/launch-diff.txt"
    note "launch screen before vs after this change: $PCT% of pixels differ$(awk -v p="$PCT" 'BEGIN { if (p < 0.5) print " — visually identical" }')"
  fi
fi
if [ -z "$(adb shell pidof "$PKG" | tr -d '\r')" ]; then
  result=fail
  note "app process not running 45 s after launch"
else
  note "app running 45 s after launch"
fi

# 2. Back gesture/button (Android 16: predictive back)
adb shell input keyevent KEYCODE_BACK
sleep 5
shot 02-after-back
TOP="$(adb shell dumpsys activity activities | grep -m1 -E 'topResumedActivity|mResumedActivity' | tr -d '\r')"
echo "$TOP" > "$OUT/after-back.txt"
if echo "$TOP" | grep -q "$PKG"; then
  note "after back the app is still in the foreground"
else
  note "after back the app went to the background (system home screen)"
fi

# 3. Rotate to landscape (large screens / orientation)
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
sleep 8
adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 1
sleep 8
shot 03-landscape
adb shell settings put system user_rotation 0

# 4. Crash gate
adb logcat -d > "$OUT/logcat.txt"
if grep -E "FATAL EXCEPTION|AndroidRuntime: Process: $PKG|Unable to load script|ReactNativeJS.*(Invariant Violation|TypeError|ReferenceError|Error: )" "$OUT/logcat.txt" > "$OUT/crashes.txt"; then
  result=fail
  LINES="$(wc -l < "$OUT/crashes.txt" | tr -d ' ')"
  note "crash/JS error in logcat ($LINES lines, crashes.txt)"
else
  rm -f "$OUT/crashes.txt"
  note "no crashes or fatal errors in logcat"
fi


# A crash caused by missing app configuration (keys / URLs from the app's .env, absent in CI) is not a verdict on the change.
if [ "$result" = "fail" ]; then
  . "$(cd "$(dirname "$0")" && pwd)/../config-crash.sh"
  WHY="$(config_crash "$OUT/logcat.txt")"
  if [ -n "$WHY" ]; then
    result=inconclusive
    note "inconclusive: the app stops at startup because its configuration is missing in CI — \"$WHY\". Set the JAGLOSKY_APP_ENV secret (the EXPO_PUBLIC_* lines of the app's .env) and re-run"
  fi
fi

echo "$result" > "$OUT/result.txt"
echo "Smoke result: $result"
exit 0
