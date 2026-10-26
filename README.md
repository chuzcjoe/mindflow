# MindFlow

MindFlow is a native speech-to-text app for macOS and iOS, powered by the SenseVoiceSmall INT8 model. It automatically recognizes Mandarin Chinese and English. Both platforms share the model, audio reading, and transcription pipeline, with interfaces tailored to desktop and mobile use.

## iOS

Requires iOS 17 or later. Open `iOS/MindFlow.xcodeproj` and select the `MindFlowiOS` scheme.

```bash
open iOS/MindFlow.xcodeproj
# Select and launch an iPhone 18 Pro simulator, then build and install the app:
bash scripts/run-ios.sh
# Run shared-core tests, real Mandarin/English model tests, and native recording tests:
bash scripts/run-ios.sh --test
# Use real audio samples to verify the UI and recognition model when no microphone is available:
bash scripts/run-ios.sh --sample Tests/MindFlowiOSTests/Fixtures/mandarin.wav
bash scripts/run-ios.sh --sample Tests/MindFlowiOSTests/Fixtures/english.wav
# Skip the hardware recording test while running the other real-model and workflow tests:
MINDFLOW_SKIP_MICROPHONE_TEST=1 bash scripts/run-ios.sh --test
# Pass a different installed simulator UDID as the final argument:
bash scripts/run-ios.sh YOUR-SIMULATOR-UDID
```

View the simulator in Xcode → Open Developer Tool → Device Hub. The iOS 27.0 runtime available on the current Mac includes iPhone 18 Pro and Pro Max, but no standard iPhone 18 template, so the default is iPhone 18 Pro. If the runtime is not installed, install it with `xcodebuild -downloadPlatform iOS -buildVersion 27.0 -architectureVariant arm64`.

Tap the microphone button to start recording and tap it again to stop and show the transcription. After a successful transcription, the text is copied to the system clipboard automatically. You can paste it into another app, long-press to select text, or tap Copy. Microphone access is requested on first use; if access is denied, use Open Microphone Settings in the app. Recording uses `AVAudioEngine` to save native-rate PCM to a temporary CAF file; the file is closed before it is read and converted to 16 kHz mono for recognition. The `AVAudioSession` is released during transcription. Recording is cancelled and its temporary file removed when the app enters the background or an incoming call interrupts it; any previous result is kept. This version works only while the app is in the foreground and does not include macOS global shortcuts or a system keyboard extension.

The model stays loaded until the process exits. Its first download is about 239 MB and is verified with SHA-256; subsequent recognition runs offline on the device. The model is stored in the app sandbox at `Library/Application Support/MindFlow/Models/SenseVoice/`. Development scripts can copy an existing model cache on this Mac to the selected simulator to avoid another download; the app still performs its full integrity check when loading. The model is not bundled in the app.

`--test` grants microphone access only to the selected simulator's MindFlow app. The recording test uses the same `AVAudioEngine` recorder as the app. Model integration tests use fixed WAV files instead of recording, run the actual iOS SenseVoice engine, verify Mandarin and English output, and check that temporary transcription files are removed; they do not use canned recognition text. The sample audio is included only in the test bundle.

`--sample` works only with Debug simulator builds. The script copies the specified WAV into the simulator's development sandbox, substitutes it for microphone input, and automatically runs the start, stop, and real-model transcription flow. The UI shows the result and a “Simulator Sample Test” label. Tapping the recording button again continues to use that sample. Running `bash scripts/run-ios.sh` without `--sample` restores normal microphone input. This audio substitution is not included in device or Release builds. Sample files and validation JSON are development data stored in the selected simulator's Documents directory.

On the current Mac, the default input and output device (“连我”) times out during the simulator hardware recording test, so that test currently fails. Use a working audio device and rerun the full `--test`, or verify microphone recording on a physical iPhone. Mandarin and English sample recognition does not depend on that device.

To run on a physical iPhone, select your developer Team in Xcode under Signing & Capabilities, change the Bundle Identifier if needed, then choose a paired iPhone as the run destination. The command-line script uses local simulator signing only and does not configure or modify your Apple developer account.

Before testing the physical microphone, stop Device Hub screen sharing using **More Actions → Stop Screen Sharing** and stop iPhone Mirroring if active. [Apple documents that the physical device's microphone is unavailable during Device Hub interaction](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub); audio may contain only silence. The USB cable can stay connected for builds and installation.

For local troubleshooting only, launch with `--audio-diagnostics` to write the latest audio format, frame count, signal levels, and recognition character count under `Library/Caches/MindFlow/AudioDiagnostics/`. These files contain no recording audio or transcript text. Diagnostics are disabled on a normal launch.

The iOS icon uses generated artwork in `Support/Icons/MindFlow-iOS-master.png`. The generation prompt is saved in `Support/Icons/ios-icon-prompt.txt`. Run `swift scripts/make-ios-icon.swift` to prepare its opaque 1024 × 1024 app asset; iOS applies the outer corner mask.

## macOS

Requires an Apple Silicon Mac, macOS 14 or later, and Swift 6 or later (Xcode or Command Line Tools).

```bash
bash scripts/build-app.sh
open dist/MindFlow.app
```

The first build downloads Swift packages from the internet. On first use, the app downloads the approximately 239 MB SenseVoiceSmall INT8 model and vocabulary; subsequent runs reuse the local cache. No API key is required. If a SenseVoice cache already exists, it is reused without downloading again.

The interface shows model download and loading progress and lets you retry if model preparation fails. Recording and transcription run locally after setup and can be used offline.

1. Once the model is ready, click **Start Speaking**. The first recording requests microphone access from macOS.
2. Speak Mandarin or English, then click the same button again to stop.
3. Wait for local transcription. The text appears under **Recognition Result** and is copied to the system clipboard automatically, ready to paste with `Command + V`. You can also select the text or click Copy. The result shows transcription time, excluding model loading and recording.

Each successful transcription replaces the previous result and the clipboard contents with the full recognized text, even when two consecutive transcriptions are identical. If a recording is too short, contains no recognized speech, or fails to transcribe, the previous result and clipboard contents are kept. Recordings are temporary WAV files and are deleted after success or failure; an in-progress recording is also cleaned up when the app exits. Transcribed text stays in the current window and is not saved to a history file.

## Custom recording shortcut

Click the field in **Recording Shortcut** on the main screen and press the key combination you want, for example `Control + Option + Space`. The setting is saved immediately and persists across app launches. No shortcut is assigned by default; choose one yourself.

- While MindFlow is running and the model is ready, press and release the shortcut once to start recording, then again to stop and transcribe. When the shortcut is used while another app's text field is active, the transcription is automatically pasted there after success.
- The shortcut and the recording button share the same workflow. You can start with one and stop with the other.
- Starting with the shortcut shows a compact recording indicator at the bottom center of the screen containing the mouse pointer. It displays live microphone levels and elapsed time, stays above other apps, and does not take keyboard focus or intercept clicks. It disappears as soon as recording ends, including when stopped with the app button, cancelled, or interrupted by a capture error. Starting with the app button keeps its existing in-window indicator.
- Recording is not triggered while you are entering a shortcut. Press `Esc` to cancel a change, or click the `×` beside the field to clear the shortcut.
- If the combination conflicts with a system or app menu shortcut, MindFlow asks you to choose another.
- The shortcut cannot be changed while recording, waiting for microphone permission, or transcribing. Repeated triggers during model setup or transcription do not start another recording.
- The recording shortcut itself does not need Accessibility or Input Monitoring permission. Cross-app automatic input requires Accessibility permission, and recording still requires microphone access. The shortcut is inactive after MindFlow quits.

## Automatic input on Mac

1. In MindFlow, click **Enable Accessibility Permission** in **Automatic Shortcut Input**, then follow the system prompt to allow MindFlow. You can also add `dist/MindFlow.app` under System Settings → Privacy & Security → Accessibility and enable it. See [Apple's accessibility permission instructions](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac).
2. Click the text field in another app where you want the text inserted. Use the assigned shortcut to start and stop recording.
3. After transcription, MindFlow pastes the text at the insertion point and leaves it on the clipboard. It does not press Return or submit a form.

Automatic input runs only when the shortcut is used to stop recording. You can start with the app button and stop with the shortcut. If you stop with the app button, the result is copied to the clipboard as usual.

When the shortcut stops recording, MindFlow records the target app and text field, then checks that focus is still there after transcription. It will not paste if transcription fails, Accessibility permission is unavailable, no text field is found, focus has changed, or the clipboard was modified while it waited. The result remains visible in MindFlow, with an explanation in the interface. Password fields are never filled automatically; apps that do not expose a standard text input focus may require manual paste.

The implementation uses the Accessibility API only to identify the focused control and its type, then sends `Command + V` to the target process. It does not read the full contents of the target text field, move the mouse, activate another app, or require Apple Events automation permission. The iOS app continues to copy results automatically.

## Model and implementation

- UI: SwiftUI. macOS recording: `AVAudioRecorder`, 16 kHz mono PCM WAV. iOS recording: `AVAudioEngine`, native-rate PCM CAF, converted to 16 kHz mono before recognition.
- Model runtime: Alibaba FunAudioLLM SenseVoiceSmall through sherpa-onnx 1.13.8 and ONNX Runtime 1.28.2, using the CPU path. The INT8 weights are about 239 MB; inference uses up to four threads.
- SenseVoice weights: [sherpa-onnx converted model](https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17), pinned to revision `2365baeacb507f821a0c8120fcee3d484dba7a07`. Downloaded files are checked for size and SHA-256. The model automatically recognizes Mandarin and English and converts speech to written forms such as numerals. Recordings longer than 20 seconds are split at low-energy boundaries.
- Model and vocabulary cache: `~/Library/Application Support/MindFlow/Models/SenseVoice/`.
- AVFoundation handles audio reading and resampling; `URLSession` downloads the model. Downloaded files are verified with SHA-256 before being written to the model cache.
- Language is detected automatically, and recognized text stays in the original language.
- The UI shows download, loading, recording, transcription, and error states and disables repeated actions while work is in progress.
- Global shortcuts use KeyboardShortcuts 1.15.0, pinned for compatibility with the current Command Line Tools. Combinations are saved by the native shortcut recorder to the app's UserDefaults. A system hotkey API handles key-up events without monitoring ordinary text input.

Closing all windows quits the app. If microphone access was denied, use **Open Microphone Settings** in the app, grant access, and try recording again.

## Verification

```bash
bash scripts/test.sh
# Transcribe audio with the real model without using a microphone:
swift run MindFlowCheck /absolute/path/to/chinese.wav /absolute/path/to/english.wav
# Verify the first-download flow (about 239 MB) with an empty cache directory:
swift run MindFlowCheck --cache-dir /tmp/mindflow-model-test /absolute/path/to/chinese.wav
```

Open `Package.swift` in Xcode to browse and debug the source. For actual microphone authorization and everyday use, run `dist/MindFlow.app` so macOS can read the app's microphone usage description.

The build script uses the single valid Apple Development signing identity in the local keychain, or the identity explicitly selected with `MINDFLOW_CODESIGN_IDENTITY` (certificate name or SHA-1 fingerprint). It stops if automatic selection is ambiguous or no identity is available. Keep the same certificate-based signing requirement across updates so macOS can recognize the updated app for privacy permissions. Switching from an older ad-hoc build to this signing identity requires granting microphone and Accessibility access once again; an outdated Accessibility entry may need to be removed and the current `dist/MindFlow.app` added again. See [Apple's designated requirements documentation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

For development without a signing certificate, explicitly use `MINDFLOW_CODESIGN_IDENTITY=- bash scripts/build-app.sh`; privacy grants may stop matching after every update. Distribution to other computers requires Developer ID signing and notarization.

After signing and validation succeed, the build script atomically replaces the app and does not force-quit a running older version. After an update, quit the old version and reopen `dist/MindFlow.app` to use the new one.

Test audio comes from the [FunASR Mandarin sample](https://isv-data.oss-cn-hangzhou.aliyuncs.com/ics/MaaS/ASR/test_audio/BAC009S0764W0121.wav) and the [English sample from whisper.cpp](https://github.com/ggml-org/whisper.cpp/blob/master/samples/jfk.wav). The CLI reports the actual transcription time for each run; timing varies with recording length, noise, and hardware.

Workflow tests cover microphone permission, recordings that are too short, missing recognition results, recovery after transcription errors, duplicate-action protection, temporary recording cleanup, long-recording segmentation, native audio reading and resampling, and shortcut start/stop events, duplicate registration protection, and repeated triggers while waiting for permission.

Shortcut automation tests use an injected event registrar to verify the recording workflow. Automatic input tests use a separate test clipboard and mock target to cover insertion only when the shortcut stops recording, identical consecutive results, transcription failure, missing or revoked permission, focus changes, and clipboard changes. Tests do not send real keystrokes to other apps. To verify actual cross-app input, grant Accessibility permission and test it directly.

Recording-indicator tests verify that it is shown only after shortcut capture actually starts, hidden before transcription, absent after permission denial or capture startup failure, and dismissed after button stop, cancellation, capture failure, controller replacement, or app disconnection. The tests inject a presentation spy and do not open floating windows.

## Third-party licenses

- [sherpa-onnx — Apache-2.0](https://github.com/k2-fsa/sherpa-onnx)
- [ONNX Runtime — MIT](https://github.com/microsoft/onnxruntime)
- [KeyboardShortcuts — MIT](https://github.com/sindresorhus/KeyboardShortcuts)
- [SenseVoiceSmall / Alibaba FunAudioLLM](https://github.com/QwenAudio/SenseVoice): code and model weights have separate terms. These model weights are governed by the [FunASR Model Open Source License Agreement v1.1](https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE). The ONNX-converted version used here retains that license reference.

The distribution includes the upstream license notices in `THIRD_PARTY_NOTICES.md`.
