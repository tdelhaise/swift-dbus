#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if command -v dbus-run-session >/dev/null 2>&1; then
  echo "[swift-dbus] Running tests inside dbus-run-session…" >&2
  exec dbus-run-session -- swift test "$@"
else
  echo "[swift-dbus] Warning: dbus-run-session introuvable, exécution directe de swift test." >&2
  exec swift test "$@"
fi
