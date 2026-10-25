#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# Some Command Line Tools versions ship TestingMacros without registering its
# plugin search path with Swift Build. Load that bundled plugin explicitly.
SWIFT_BIN="$(xcrun --find swift)"
TEST_PLUGIN="$(dirname "$SWIFT_BIN")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ -f "$TEST_PLUGIN" ]; then
    swift test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$TEST_PLUGIN"
else
    swift test --disable-xctest
fi
