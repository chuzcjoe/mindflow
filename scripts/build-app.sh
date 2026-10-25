#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

CONFIGURATION="${1:-release}"
swift build -c "$CONFIGURATION" --product MindFlow
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
mkdir -p "$PROJECT_DIR/dist"
STAGING_DIR="$(mktemp -d "$PROJECT_DIR/dist/.mindflow-build.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP_DIR="$STAGING_DIR/MindFlow.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/MindFlow" "$APP_DIR/Contents/MacOS/MindFlow"
cp Support/Info.plist "$APP_DIR/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.md "$APP_DIR/Contents/Resources/"

if [ ! -f .build/AppIcon.icns ] || [ scripts/make-icon.swift -nt .build/AppIcon.icns ]; then
    swift scripts/make-icon.swift "$PROJECT_DIR/.build/AppIcon.iconset"
    iconutil -c icns .build/AppIcon.iconset -o .build/AppIcon.icns
fi
cp .build/AppIcon.icns "$APP_DIR/Contents/Resources/"

# SwiftPM dependencies may ship resource bundles alongside their executables.
while IFS= read -r -d '' RESOURCE; do
    cp -R "$RESOURCE" "$APP_DIR/Contents/Resources/"
done < <(find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -print0)

codesign --force --sign - --entitlements Support/MindFlow.entitlements "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

# Publish a complete bundle in one filesystem operation. This also allows a
# previous version to keep running until the user is ready to quit and reopen.
python3 - "$APP_DIR" "$PROJECT_DIR/dist/MindFlow.app" <<'PY'
import ctypes
import os
import sys

source, destination = sys.argv[1:]
if os.path.exists(destination):
    libc = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
    swap = libc.renamex_np
    swap.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    swap.restype = ctypes.c_int
    if swap(os.fsencode(source), os.fsencode(destination), 0x00000002) != 0:  # RENAME_SWAP
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))
else:
    os.replace(source, destination)
PY
echo "Built: $PROJECT_DIR/dist/MindFlow.app"
