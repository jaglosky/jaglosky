#!/usr/bin/env bash
# App configuration for CI builds. $APP_ENV holds KEY=value lines (the JAGLOSKY_APP_ENV secret, e.g. the app's .env).
# Only EXPO_PUBLIC_* lines are exported to later steps: those values are compiled into the app anyway (anyone can
# read them from the store build), while everything else in a .env (auth tokens, service keys) stays out of CI.
set -uo pipefail
[ -n "${APP_ENV:-}" ] || exit 0
names=(); ignored=0
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"; line="${line#export }"
  case "$line" in ''|\#*) continue ;; esac
  if [[ "$line" =~ ^(EXPO_PUBLIC_[A-Za-z0-9_]+)=(.*)$ ]]; then
    name="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
    if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then value="${BASH_REMATCH[1]}"; fi
    [ "${#value}" -ge 12 ] && echo "::add-mask::$value"
    { echo "$name<<__JAGLOSKY_ENV__"; echo "$value"; echo "__JAGLOSKY_ENV__"; } >> "$GITHUB_ENV"
    names+=("$name")
  else
    ignored=$((ignored + 1))
  fi
done <<< "$APP_ENV"
echo "🔧 App config for the build: ${#names[@]} EXPO_PUBLIC_* variable(s) from JAGLOSKY_APP_ENV (${names[*]:-none})$([ "$ignored" -gt 0 ] && echo "; $ignored other line(s) ignored")"
