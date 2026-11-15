#!/usr/bin/env bash
# Installs the app's JS dependencies with ITS package manager — the lockfile decides (same rule as
# packages/core/src/pm.ts). No lockfile → nothing to install (native / Flutter apps).
set -euo pipefail
if [ -f package-lock.json ]; then
  npm ci --no-audit --no-fund
elif [ -f yarn.lock ]; then
  corepack enable >/dev/null 2>&1 || true   # packageManager field (Yarn 2+) → the right Yarn version
  if grep -q '^__metadata:' yarn.lock; then
    yarn install --immutable
  else
    yarn install --frozen-lockfile --non-interactive --network-timeout 600000
  fi
elif [ -f pnpm-lock.yaml ]; then
  corepack enable >/dev/null 2>&1 || true
  pnpm install --frozen-lockfile
elif [ -f package.json ]; then
  echo "⚠️  package.json without a lockfile — dependencies not installed (native facts and the vulnerability scan need one)"
fi
