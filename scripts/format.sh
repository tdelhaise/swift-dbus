#!/usr/bin/env bash
set -euo pipefail

# --- SwiftFormat ---
swift-format format --in-place --configuration .swift-format --recursive .

# --- SwiftLint ---
# Sur Linux, SourceKit peut nécessiter LD_LIBRARY_PATH pour éviter:
# "Loading libsourcekitdInProc.so failed"
if ! swiftlint version >/dev/null 2>&1; then
  echo "swiftlint introuvable. Installe-le (brew install swiftlint) ou compile depuis la source."
  exit 1
fi

# Essayer d’enrichir LD_LIBRARY_PATH automatiquement si vide
if [[ -z "${LD_LIBRARY_PATH:-}" ]]; then
  if command -v swift >/dev/null 2>&1; then
    # Chemin générique toolchain
    SWIFT_BIN="$(dirname "$(command -v swift)")"
    SWIFT_HOME="$(dirname "$SWIFT_BIN")"
    export LD_LIBRARY_PATH="$SWIFT_HOME/lib:$SWIFT_HOME/lib/swift/linux"
  fi
fi

swiftlint --fix || true
swiftlint lint --strict
