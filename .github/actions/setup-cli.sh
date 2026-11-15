#!/bin/bash
# Makes the Jaglosky CLI runnable from the action checkout and exports JAGLOSKY_ROOT for the later steps.
# Two layouts, same paths:
#   distribution (the public repo, tags v1.x) — the bundled CLI is already there and needs no install; only the
#     agent has one runtime dependency (the agent SDK), installed with --agent;
#   source checkout (development) — install the workspace and run the TypeScript through ./jaglosky.
# Usage: bash setup-cli.sh [--agent]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
echo "JAGLOSKY_ROOT=$ROOT" >> "$GITHUB_ENV"
if [ -f "$ROOT/packages/cli/src/jaglosky.mjs" ]; then
  if [ "${1:-}" = "--agent" ]; then
    # The one package the bundle does not contain (package.json → jaglosky.agentSdk), installed next to it.
    SDK="$(node -p "require('$ROOT/package.json').jaglosky.agentSdk.join(' ')")"
    # shellcheck disable=SC2086
    (cd "$ROOT" && npm install --no-save --ignore-scripts --no-audit --no-fund --silent $SDK)
  fi
  # App repos on pnpm without a packageManager field still need a pnpm binary (install-deps.sh, the agent's installs).
  if [ -f "${GITHUB_WORKSPACE:-.}/pnpm-lock.yaml" ] && ! command -v pnpm >/dev/null 2>&1; then
    npm install -g pnpm@10 --silent
  fi
  echo "Jaglosky $(node -p "require('$ROOT/package.json').version") (bundle)"
else
  npm install -g pnpm@10 --silent
  (cd "$ROOT" && pnpm install --frozen-lockfile --silent)
  echo "Jaglosky (source checkout)"
fi
