#!/usr/bin/env bash
# config_crash <log file> → prints the first log line that says the app died because its configuration is missing
# (API keys / backend URLs that come from the app's .env and are not in CI). Such a crash says nothing about the
# change under test, so the smoke test reports "inconclusive" instead of "fail".
# Usage: source this file, or run it: config-crash.sh <log file>
CONFIG_CRASH_RE='API key must be set|api[ _-]?key (is |was )?(required|missing|not set|not provided|undefined)|supabase(Url|Key) is required|EXPO_PUBLIC_[A-Z0-9_]+ (is |was )?(missing|required|not set|undefined)|(environment|env) variables? .{0,80}(missing|not set|required|undefined)|missing (required )?(environment|env) variable|Default FirebaseApp is not initialized|No Firebase App .{0,40}has been created|(dsn|client ?id|project ?id) (is |was )?(required|missing|not set)'
config_crash() {
  grep -iE "AndroidRuntime|ReactNativeJS|RCTFatal|Unhandled JS Exception|uncaught exception|Error" "$1" 2>/dev/null | grep -iE -m1 "$CONFIG_CRASH_RE" | sed -E 's/^.*(AndroidRuntime|ReactNativeJS): //' | cut -c1-200
}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then config_crash "$1"; fi
