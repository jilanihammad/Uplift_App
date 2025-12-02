#!/usr/bin/env bash
set -euo pipefail

APK_PATH=${1:-build/app/outputs/flutter-apk/app-release.apk}
if [[ ! -f "$APK_PATH" ]]; then
  echo "Release APK not found at $APK_PATH"
  exit 1
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

unzip -qq "$APK_PATH" -d "$WORKDIR/apk"

# Common secret patterns (API keys, tokens). Extend as needed.
PATTERNS=("sk-" "api_key" "secret" "AIza" "ghp_")
FOUND=0
for pattern in "${PATTERNS[@]}"; do
  if rg -n --hidden --color=never "$pattern" "$WORKDIR/apk" >/tmp/scan_release_hits 2>/dev/null; then
    echo "Potential secret pattern '$pattern' found:"
    cat /tmp/scan_release_hits
    FOUND=1
  fi
  rm -f /tmp/scan_release_hits
done

if [[ $FOUND -ne 0 ]]; then
  echo "\n⚠️  Potential secrets detected in release artifact. Review and remove before shipping."
  exit 2
fi

echo "✅ No known secret patterns found in $APK_PATH"
