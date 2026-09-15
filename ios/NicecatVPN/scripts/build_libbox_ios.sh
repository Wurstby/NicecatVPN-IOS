#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT/Vendor"
SING_BOX_REF="${SING_BOX_REF:-v1.14.1}"
WORK_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/nicecat-sing-box"
SOURCE_DIR="$WORK_DIR/sing-box"

mkdir -p "$VENDOR_DIR" "$WORK_DIR"

if [ ! -d "$SOURCE_DIR/.git" ]; then
  git clone --depth 1 --branch "$SING_BOX_REF" https://github.com/SagerNet/sing-box.git "$SOURCE_DIR"
else
  git -C "$SOURCE_DIR" fetch --depth 1 origin "refs/tags/$SING_BOX_REF:refs/tags/$SING_BOX_REF"
  git -C "$SOURCE_DIR" checkout -f "$SING_BOX_REF"
fi

export PATH="$(go env GOPATH)/bin:$PATH"
go install -v github.com/sagernet/gomobile/cmd/gomobile@v0.1.13
go install -v github.com/sagernet/gomobile/cmd/gobind@v0.1.13

(
  cd "$SOURCE_DIR"
  rm -rf Libbox.xcframework
  go run ./cmd/internal/build_libbox -target apple -platform ios
)

rm -rf "$VENDOR_DIR/Libbox.xcframework"
cp -R "$SOURCE_DIR/Libbox.xcframework" "$VENDOR_DIR/Libbox.xcframework"
echo "Libbox.xcframework is ready at $VENDOR_DIR/Libbox.xcframework"
