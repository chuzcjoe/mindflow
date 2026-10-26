import Foundation
import MindFlowKit
import Testing
@testable import MindFlow

@Suite @MainActor
struct RecordingShortcutTests {
    @Test(.timeLimit(.minutes(1)))
    func testIndicatorWaitsForRealRecordingAndHidesBeforeTranscription() async throws {
        var keyUp: RecordingShortcutHandler.Action?
        let indicator = ShortcutIndicatorSpy()
        let handler = RecordingShortcutHandler(recordingIndicator: indicator, register: { keyUp = $0 })
        let recorder = ShortcutTestRecorder()
        recorder.holdPermission = true
        let transcriber = ShortcutTestTranscriber(onTranscribe: { #expect(!indicator.isVisible) })
        let controller = DictationController(transcriber: transcriber, recorder: recorder)
        await controller.prepare()
        handler.connect(to: controller)
        let action = try #require(keyUp)
        let pending = Task { await action() }
        await recorder.waitForPermissionRequest()
        #expect(!indicator.isVisible)
        recorder.grantPermission()
        await pending.value
        #expect(indicator.isVisible)
        #expect(indicator.showCount == 1)
        await action()
        #expect(!indicator.isVisible)
        #expect(indicator.hideCount == 1)
        #expect(controller.phase == .ready)
    }

    @Test(arguments: ["permissionDenied", "startFailed"])
    func testIndicatorNeverAppearsWhenCaptureCannotStart(_ failure: String) async throws {
        var keyUp: RecordingShortcutHandler.Action?
        let indicator = ShortcutIndicatorSpy()
        let handler = RecordingShortcutHandler(recordingIndicator: indicator, register: { keyUp = $0 })
        let recorder = ShortcutTestRecorder()
        recorder.permissionGranted = failure != "permissionDenied"
        recorder.failStart = failure == "startFailed"
        let controller = DictationController(transcriber: ShortcutTestTranscriber(), recorder: recorder)
        await controller.prepare()
        handler.connect(to: controller)
        let action = try #require(keyUp)
        await action()
        #expect(controller.phase == .ready)
        #expect(controller.errorMessage != nil)
        #expect(!indicator.isVisible)
        #expect(indicator.showCount == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func testButtonRecordingDoesNotShowIndicatorAndButtonStopDismissesShortcutIndicator() async throws {
        var keyUp: RecordingShortcutHandler.Action?
        let indicator = ShortcutIndicatorSpy()
        let handler = RecordingShortcutHandler(recordingIndicator: indicator, register: { keyUp = $0 })
        let controller = DictationController(transcriber: ShortcutTestTranscriber(), recorder: ShortcutTestRecorder())
        await controller.prepare()
        handler.connect(to: controller)
        let action = try #require(keyUp)
        await controller.toggleRecording()
        #expect(!indicator.isVisible)
        await action()
        #expect(indicator.showCount == 0)
        await action()
        #expect(indicator.isVisible)
        await controller.toggleRecording()
        await indicator.waitUntilHidden()
        #expect(indicator.hideCount == 1)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["cancel", "captureFailure", "shutdown"])
    func testIndicatorIsDismissedWhenRecordingIsInterrupted(_ interruption: String) async throws {
        var keyUp: RecordingShortcutHandler.Action?
        let indicator = ShortcutIndicatorSpy()
        let handler = RecordingShortcutHandler(recordingIndicator: indicator, register: { keyUp = $0 })
        let recorder = ShortcutTestRecorder()
        let controller = DictationController(transcriber: ShortcutTestTranscriber(), recorder: recorder)
        await controller.prepare()
        handler.connect(to: controller)
        let action = try #require(keyUp)
        await action()
        #expect(indicator.isVisible)
        switch interruption {
        case "cancel": controller.cancelRecording()
        case "captureFailure": recorder.onFailure?(URLError(.cannotOpenFile))
        default: controller.shutDown()
        }
        await indicator.waitUntilHidden()
        #expect(indicator.hideCount == 1)
        #expect(!FileManager.default.fileExists(atPath: recorder.url.path))
    }

    @Test(.timeLimit(.minutes(1)))
    func testLatePermissionCannotShowIndicatorForReplacedControllerAndDisconnectHidesIt() async throws {
        var keyUp: RecordingShortcutHandler.Action?
        let indicator = ShortcutIndicatorSpy()
        let handler = RecordingShortcutHandler(recordingIndicator: indicator, register: { keyUp = $0 })
        let recorder = ShortcutTestRecorder()
        recorder.holdPermission = true
        let first = DictationController(transcriber: ShortcutTestTranscriber(), recorder: recorder)
        let second = DictationController(transcriber: ShortcutTestTranscriber(), recorder: ShortcutTestRecorder())
        await first.prepare()
        await second.prepare()
        handler.connect(to: first)
        let action = try #require(keyUp)
        let pending = Task { await action() }
        await recorder.waitForPermissionRequest()
        handler.connect(to: second)
        recorder.grantPermission()
        await pending.value
        #expect(indicator.showCount == 0)
        first.shutDown()
        await action()
        #expect(indicator.isVisible)
        handler.disconnect()
        #expect(!indicator.isVisible)
        second.shutDown()
    }

    @Test
    func testShortcutCapturesInputOnlyOnStopAndInsertsEverySuccessfulResult() async throws {
        var keyUp: RecordingShortcutHandler.Action?
        var captures = 0
        var inserted: [String] = []
        let handler = RecordingShortcutHandler(prepareInsertion: {
            captures += 1
            return { inserted.append($0) }
        }, register: { keyUp = $0 })
        let controller = DictationController(transcriber: ShortcutTestTranscriber(), recorder: ShortcutTestRecorder())
        await controller.prepare()
        handler.connect(to: controller)
        let action = try #require(keyUp)
        for index in 0..<2 {
            await action()
            #expect(captures == index)
            await action()
        }
        #expect(captures == 2)
        #expect(inserted == ["快捷键转写成功", "快捷键转写成功"])
    }

    @Test
    func testOnlyEndingWithShortcutTriggersInsertion() async throws {
        var keyUp: RecordingShortcutHandler.Action?
        var inserted: [String] = []
        let handler = RecordingShortcutHandler(prepareInsertion: {
            { inserted.append($0) }
        }, register: { keyUp = $0 })
        let controller = DictationController(transcriber: ShortcutTestTranscriber(), recorder: ShortcutTestRecorder())
        await controller.prepare()
        handler.connect(to: controller)
        let action = try #require(keyUp)
        await action()
        await controller.toggleRecording() // End with the app button.
        #expect(inserted.isEmpty)
        await controller.toggleRecording() // Start with the app button.
        await action()
        #expect(inserted == ["快捷键转写成功"])
    }

    @Test
    func testFailedShortcutTranscriptionDoesNotInsertPreviousResult() async throws {
        var keyUp: RecordingShortcutHandler.Action?
        var inserted: [String] = []
        let handler = RecordingShortcutHandler(prepareInsertion: {
            { inserted.append($0) }
        }, register: { keyUp = $0 })
        let transcriber = ShortcutTestTranscriber()
        let controller = DictationController(transcriber: transcriber, recorder: ShortcutTestRecorder())
        await controller.prepare()
        handler.connect(to: controller)
        let action = try #require(keyUp)
        await action()
        await action()
        await transcriber.failNextTranscription()
        await action()
        await action()
        #expect(controller.errorMessage != nil)
        #expect(inserted == ["快捷键转写成功"])
    }

    @Test
    func testOneShortcutStartsThenStopsRecordingWithoutDuplicateHandlers() async throws {
        var keyUp: RecordingShortcutHandler.Action?
        var registrations = 0
        let handler = RecordingShortcutHandler(register: { action in
            registrations += 1
            keyUp = action
        })
        let recorder = ShortcutTestRecorder()
        let controller = DictationController(transcriber: ShortcutTestTranscriber(), recorder: recorder)
        await controller.prepare()
        handler.connect(to: controller)
        handler.connect(to: controller)
        let action = try #require(keyUp)

        await action()
        #expect(controller.phase == .recording)
        #expect(recorder.starts == 1)
        await action()
        #expect(controller.phase == .ready)
        #expect(controller.transcript == "快捷键转写成功")
        #expect(!FileManager.default.fileExists(atPath: recorder.url.path))
        handler.connect(to: controller)
        #expect(registrations == 1)
    }

    @Test
    func testReconnectingRoutesShortcutToCurrentWindowController() async throws {
        var keyUp: RecordingShortcutHandler.Action?
        var registrations = 0
        let handler = RecordingShortcutHandler(register: { registrations += 1; keyUp = $0 })
        let firstRecorder = ShortcutTestRecorder()
        let secondRecorder = ShortcutTestRecorder()
        let first = DictationController(transcriber: ShortcutTestTranscriber(), recorder: firstRecorder)
        let second = DictationController(transcriber: ShortcutTestTranscriber(), recorder: secondRecorder)
        await first.prepare()
        await second.prepare()
        handler.connect(to: first)
        handler.connect(to: second)
        let action = try #require(keyUp)
        await action()
        #expect(firstRecorder.starts == 0)
        #expect(secondRecorder.starts == 1)
        #expect(second.phase == .recording)
        second.shutDown()
        handler.connect(to: second)
        #expect(registrations == 1)
    }

    @Test
    func testShortcutCannotRecordBeforeModelIsReady() async throws {
        var keyUp: RecordingShortcutHandler.Action?
        let handler = RecordingShortcutHandler(register: { keyUp = $0 })
        let recorder = ShortcutTestRecorder()
        let controller = DictationController(transcriber: ShortcutTestTranscriber(), recorder: recorder)
        handler.connect(to: controller)
        let action = try #require(keyUp)
        await action()
        #expect(controller.phase == .preparing)
        #expect(recorder.permissionRequests == 0)
        #expect(recorder.starts == 0)
        handler.connect(to: controller)
    }

    @Test
    func testRepeatedShortcutWhileAwaitingMicrophonePermissionIsIgnored() async throws {
        var keyUp: RecordingShortcutHandler.Action?
        let handler = RecordingShortcutHandler(register: { keyUp = $0 })
        let recorder = ShortcutTestRecorder()
        recorder.holdPermission = true
        let controller = DictationController(transcriber: ShortcutTestTranscriber(), recorder: recorder)
        await controller.prepare()
        handler.connect(to: controller)
        let action = try #require(keyUp)
        let pending = Task { await action() }
        await recorder.waitForPermissionRequest()
        await action()
        #expect(controller.phase == .requestingPermission)
        #expect(recorder.permissionRequests == 1)
        #expect(recorder.starts == 0)
        recorder.grantPermission()
        await pending.value
        #expect(controller.phase == .recording)
        #expect(recorder.starts == 1)
        controller.shutDown()
        handler.connect(to: controller)
    }
}

private actor ShortcutTestTranscriber: SpeechTranscribing {
    private var fails = false
    private let onTranscribe: @MainActor @Sendable () -> Void
    init(onTranscribe: @escaping @MainActor @Sendable () -> Void = {}) {
        self.onTranscribe = onTranscribe
    }
    func failNextTranscription() { fails = true }
    func prepare(progress: @escaping @Sendable (ModelPreparation) -> Void) async throws { }
    func transcribe(audioURL: URL) async throws -> String {
        await onTranscribe()
        if fails { throw URLError(.cannotDecodeContentData) }
        return "快捷键转写成功"
    }
}

@MainActor
private final class ShortcutTestRecorder: AudioRecording {
    var onFailure: ((Error) -> Void)?
    var currentTime: TimeInterval = 1
    var level: Double = 0.5
    var starts = 0
    var permissionRequests = 0
    var holdPermission = false
    var permissionGranted = true
    var failStart = false
    private var permissionCompletion: CheckedContinuation<Bool, Never>?
    private var permissionWaiter: CheckedContinuation<Void, Never>?
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("mindflow-shortcut-test-\(UUID().uuidString).wav")

    func requestPermission() async -> Bool {
        permissionRequests += 1
        guard holdPermission else { return permissionGranted }
        return await withCheckedContinuation { continuation in
            permissionCompletion = continuation
            permissionWaiter?.resume()
            permissionWaiter = nil
        }
    }
    func waitForPermissionRequest() async {
        if permissionCompletion != nil { return }
        await withCheckedContinuation { permissionWaiter = $0 }
    }
    func grantPermission() {
        permissionCompletion?.resume(returning: true)
        permissionCompletion = nil
    }
    func start() throws {
        starts += 1
        if failStart { throw URLError(.cannotCreateFile) }
        try Data("test recording".utf8).write(to: url)
    }
    func stop() throws -> URL { url }
    func discard() { try? FileManager.default.removeItem(at: url) }
}

@MainActor
private final class ShortcutIndicatorSpy: RecordingIndicatorPresenting {
    private(set) var isVisible = false
    private(set) var showCount = 0
    private(set) var hideCount = 0
    private var hideWaiter: CheckedContinuation<Void, Never>?

    func show(for controller: DictationController) {
        #expect(controller.phase == .recording)
        isVisible = true
        showCount += 1
    }

    func hide() {
        isVisible = false
        hideCount += 1
        hideWaiter?.resume()
        hideWaiter = nil
    }

    func waitUntilHidden() async {
        guard isVisible else { return }
        await withCheckedContinuation { hideWaiter = $0 }
    }
}
