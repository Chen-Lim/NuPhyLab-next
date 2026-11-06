#!/bin/bash
set -euo pipefail
KIT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATION_TMP="$(mktemp -d "${TMPDIR:-/tmp}/lab-selection-ai-validation.XXXXXX")"
trap 'rm -rf "$VALIDATION_TMP"' EXIT
mkdir -p "$VALIDATION_TMP/module-cache"
xcrun swiftc -swift-version 5 -parse-as-library -module-name AIProtocolValidation \
  -module-cache-path "$VALIDATION_TMP/module-cache" \
  "$KIT_ROOT"/Sources/LabSelectionAI/*.swift \
  "$KIT_ROOT/Validation/Validation.swift" -o "$VALIDATION_TMP/validate"
"$VALIDATION_TMP/validate"
