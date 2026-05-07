#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building DeskviewCapture for arm64-apple-macosx..."
swift build -c release --arch arm64

OUT_DIR="../bin"
mkdir -p "$OUT_DIR"
cp .build/arm64-apple-macosx/release/DeskviewCapture "$OUT_DIR/deskview-capture"
chmod +x "$OUT_DIR/deskview-capture"

echo "Built: $OUT_DIR/deskview-capture"
