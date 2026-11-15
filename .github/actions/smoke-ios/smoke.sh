#!/usr/bin/env bash
# iOS simulator smoke test: install → launch → two screenshots → crash gate (reports + log).
# Does not stop at the first error — collects evidence, result in $OUT/result.txt.
set -uo pipefail
APP="$1"
OUT="$2"
mkdir -p "$OUT"
result=pass
note() { echo "$1" >> "$OUT/notes.txt"; echo "• $1"; }

# Newest iOS runtime + an iPhone (no SE/mini, for stable screenshots).
read -r UDID DEVICE RUNTIME < <(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
d = json.load(sys.stdin)["devices"]
best = None
for rt, devs in d.items():
    m = re.search(r"iOS-(\d+)-(\d+)", rt)
    if not m: continue
    ver = (int(m.group(1)), int(m.group(2)))
    for dev in devs:
        if dev["name"].startswith("iPhone") and "SE" not in dev["name"] and "mini" not in dev["name"]:
            if best is None or ver > best[0]:
                best = (ver, dev["udid"], dev["name"].replace(" ", "_"))
print(best[1], best[2], f"{best[0][0]}.{best[0][1]}")
')
echo "iOS $RUNTIME ($(echo "$DEVICE" | tr '_' ' '), simulator)" | tee "$OUT/device.txt"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null

BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")"
EXE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP/Info.plist")"
# Version of the built app — the release check compares it with the App Store.
{
  echo "bundle_id=$BUNDLE"
  echo "version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Info.plist" 2>/dev/null)"
  echo "build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Info.plist" 2>/dev/null)"
} > "$OUT/app-version.txt"
if ! xcrun simctl install "$UDID" "$APP" > "$OUT/install.log" 2>&1; then
  note "installing the .app failed (install.log)"
  echo fail > "$OUT/result.txt"
  exit 0
fi
BEFORE_CRASHES="$(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -c "^$EXE" || true)"

# `simctl launch` prints "<bundle>: <pid>"; simulator apps are ordinary host processes, so the PID
# can be checked on the Mac itself (launchctl labels inside the simulator changed in iOS 26).
LAUNCH="$(xcrun simctl launch "$UDID" "$BUNDLE" 2>&1)"
PID="${LAUNCH##*: }"
sleep 45
xcrun simctl io "$UDID" screenshot "$OUT/01-launch.png" > /dev/null 2>&1 || note "could not take screenshot 01-launch"
if { [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; } || pgrep -f "$UDID/.*/$EXE\.app/$EXE" > /dev/null; then
  note "app running 45 s after launch"
else
  result=fail
  note "app process not running 45 s after launch"
fi

sleep 15
xcrun simctl io "$UDID" screenshot "$OUT/02-after-60s.png" > /dev/null 2>&1 || true

# Crash gate: new .ips reports + fatal errors in the process log.
AFTER_CRASHES="$(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -c "^$EXE" || true)"
xcrun simctl spawn "$UDID" log show --last 3m --style compact --predicate "process == \"$EXE\"" > "$OUT/log.txt" 2>/dev/null || true
if [ "${AFTER_CRASHES:-0}" -gt "${BEFORE_CRASHES:-0}" ]; then
  result=fail
  note "new crash report in DiagnosticReports"
  ls -t ~/Library/Logs/DiagnosticReports | grep "^$EXE" | head -1 | xargs -I{} cp ~/Library/Logs/DiagnosticReports/{} "$OUT/" 2>/dev/null || true
fi
if grep -E "RCTFatal|Unhandled JS Exception|Invariant Violation|EXC_BAD_ACCESS|Terminating app due to uncaught exception" "$OUT/log.txt" > "$OUT/crashes.txt"; then
  result=fail
  LINES="$(wc -l < "$OUT/crashes.txt" | tr -d ' ')"
  note "fatal error in the app log ($LINES lines, crashes.txt)"
else
  rm -f "$OUT/crashes.txt"
  note "no crashes or fatal errors in the log"
fi

# A crash caused by missing app configuration (keys / URLs from the app's .env, absent in CI) is not a verdict on the change.
if [ "$result" = "fail" ]; then
  . "$(cd "$(dirname "$0")" && pwd)/../config-crash.sh"
  WHY="$(config_crash "$OUT/log.txt")"
  if [ -n "$WHY" ]; then
    result=inconclusive
    note "inconclusive: the app stops at startup because its configuration is missing in CI — \"$WHY\". Set the JAGLOSKY_APP_ENV secret (the EXPO_PUBLIC_* lines of the app's .env) and re-run"
  fi
fi

echo "$result" > "$OUT/result.txt"
echo "iOS smoke result: $result"
exit 0
