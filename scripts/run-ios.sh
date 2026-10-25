#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
MODE="run"
SAMPLE_SOURCE=""
if [ "${1:-}" = "--test" ]; then
    MODE="test"
    shift
elif [ "${1:-}" = "--sample" ]; then
    MODE="sample"
    SAMPLE_SOURCE="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve(strict=True))' "${2:?Specify a WAV file after --sample}")"
    shift 2
fi
if [ "$#" -gt 1 ]; then
    echo "Usage: bash scripts/run-ios.sh [--test | --sample file.wav] [simulator-UDID]" >&2
    exit 2
fi
SIMULATOR_ID="$(python3 scripts/ios-simulator.py "$@")"
mkdir -p .build/validation
printf '%s\n' "$SIMULATOR_ID" > .build/validation/ios-simulator-id
if ! xcrun simctl list devices booted | rg -q "$SIMULATOR_ID"; then
    xcrun simctl boot "$SIMULATOR_ID"
fi
xcrun simctl bootstatus "$SIMULATOR_ID" -b
BUILD_ACTION="build"
if [ "$MODE" = "test" ]; then BUILD_ACTION="build-for-testing"; fi
xcodebuild -project iOS/MindFlow.xcodeproj -scheme MindFlowiOS \
    -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -derivedDataPath .build/ios "$BUILD_ACTION" CODE_SIGN_IDENTITY=-
xcrun simctl install "$SIMULATOR_ID" .build/ios/Build/Products/Debug-iphonesimulator/MindFlow.app
python3 scripts/seed-ios-model.py "$SIMULATOR_ID"
if [ "$MODE" = "test" ]; then
    TEST_OPTIONS=("-only-testing:MindFlowiOSTests")
    if [ "${MINDFLOW_SKIP_MICROPHONE_TEST:-0}" = "1" ]; then
        echo "Skipping native microphone hardware test; real SenseVoice WAV tests still run."
        TEST_OPTIONS+=("-skip-testing:MindFlowiOSTests/iOSIntegrationTests/testNativeIOSAudioSessionRecords16kMonoAndReleasesTemporaryAudio")
    else
        # Only the development simulator's app receives microphone permission.
        xcrun simctl privacy "$SIMULATOR_ID" grant microphone com.mindflow.ios
    fi
    xcodebuild -project iOS/MindFlow.xcodeproj -scheme MindFlowiOS \
        -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
        -derivedDataPath .build/ios -parallel-testing-enabled NO \
        test-without-building "${TEST_OPTIONS[@]}" CODE_SIGN_IDENTITY=-
elif [ "$MODE" = "sample" ]; then
    CONTAINER="$(xcrun simctl get_app_container "$SIMULATOR_ID" com.mindflow.ios data)"
    mkdir -p "$CONTAINER/Documents"
    cp "$SAMPLE_SOURCE" "$CONTAINER/Documents/mindflow-validation.wav"
    SAMPLE_RUN_ID="$(uuidgen)"
    SIMCTL_CHILD_MINDFLOW_SAMPLE_AUDIO="$CONTAINER/Documents/mindflow-validation.wav" \
    SIMCTL_CHILD_MINDFLOW_SAMPLE_RUN_ID="$SAMPLE_RUN_ID" \
        xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" com.mindflow.ios --validate-sample
    python3 - "$CONTAINER/Documents/mindflow-sample-$SAMPLE_RUN_ID.json" <<'PY'
import json, pathlib, sys, time
report = pathlib.Path(sys.argv[1])
deadline = time.monotonic() + 45
while not report.exists():
    if time.monotonic() > deadline:
        sys.exit("Timed out waiting for real-model sample recognition.")
    time.sleep(0.2)
result = json.loads(report.read_text())
print(json.dumps(result, ensure_ascii=False, indent=2))
if not result["ready"] or result["error"] or not result["transcript"]:
    sys.exit("Sample recognition failed.")
if not result["clipboardMatchesTranscript"]:
    sys.exit("Automatic clipboard copy failed.")
PY
else
    xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" com.mindflow.ios
fi
