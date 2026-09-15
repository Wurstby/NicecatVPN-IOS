#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="NicecatVPN"

mkdir -p "$ROOT/build"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Missing xcodegen. Install it with: brew install xcodegen" >&2
  exit 1
fi

(cd "$ROOT" && xcodegen generate)

xcodebuild \
  -project "$ROOT/NicecatVPN.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$ROOT/build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_PATH="$(find "$ROOT/build/DerivedData/Build/Products/Release-iphoneos" -maxdepth 1 -name 'NicecatVPN.app' -type d | head -n 1)"
test -n "$APP_PATH"

rm -rf "$ROOT/build/Payload" "$ROOT/build/NicecatVPN-unsigned.ipa"
mkdir -p "$ROOT/build/Payload"
cp -R "$APP_PATH" "$ROOT/build/Payload/"
(cd "$ROOT/build" && zip -qry NicecatVPN-unsigned.ipa Payload)

echo "IPA output: $ROOT/build/NicecatVPN-unsigned.ipa"
