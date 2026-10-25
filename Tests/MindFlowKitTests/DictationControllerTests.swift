import Foundation
import Testing
@testable import MindFlowKit

@Suite @MainActor
struct DictationControllerTests {
    @Test
    func testEverySuccessfulRecordingPublishesTextIncludingIdenticalResults() async {
        var clipboard = "原有剪贴板内容"
        var writes: [String] = []
        let recorder = StubRecorder()
        let recognizer = StubTranscriber(output: "  重复的识别结果。  ")
        let controller = DictationController(transcriber: recognizer, recorder: recorder, onTranscription: { text in
            clipboard = text
            writes.append(text)
        })
        await controller.prepare()
        for _ in 0..<2 {
            await controller.toggleRecording()
            await controller.toggleRecording()
            #expect(clipboard == "重复的识别结果。")
        }
        #expect(writes == ["重复的识别结果。", "重复的识别结果。"])

        clipboard = "其他应用刚复制的内容"
        await recognizer.setTranscriptionFailure(true)
        await controller.toggleRecording()
        await controller.toggleRecording()
        #expect(controller.errorMessage != nil)
        #expect(clipboard == "其他应用刚复制的内容")
        #expect(writes.count == 2)
    }

    @Test
    func testClickStartThenClickStopTranscribesAndDeletesRecording() async throws {
        let recorder = StubRecorder()
        let recognizer = StubTranscriber(output: "今天测试语音输入。 Hello, MindFlow.")
        let controller = DictationController(transcriber: recognizer, recorder: recorder)
        await controller.prepare()
        await controller.toggleRecording()
        #expect(controller.phase == .recording)
        #expect(recorder.didStart)

        await controller.toggleRecording()
        #expect(controller.phase == .ready)
        #expect(controller.transcript == "今天测试语音输入。 Hello, MindFlow.")
        #expect(controller.errorMessage == nil)
        #expect(!FileManager.default.fileExists(atPath: recorder.url.path))
        let calls = await recognizer.transcriptionCount
        #expect(calls == 1)
    }

    @Test
    func testDeniedMicrophoneDoesNotStartRecording() async {
        let recorder = StubRecorder()
        recorder.permission = false
        let controller = DictationController(transcriber: StubTranscriber(), recorder: recorder)
        await controller.prepare()
        await controller.toggleRecording()
        #expect(controller.phase == .ready)
        #expect(controller.needsMicrophonePermission)
        #expect(!recorder.didStart)
        #expect(controller.errorMessage != nil)
    }

    @Test
    func testTooShortRecordingIsDeletedWithoutCallingModel() async {
        let recorder = StubRecorder()
        recorder.currentTime = 0.1
        let recognizer = StubTranscriber()
        let controller = DictationController(transcriber: recognizer, recorder: recorder)
        await controller.prepare()
        await controller.toggleRecording()
        await controller.toggleRecording()
        #expect(controller.phase == .ready)
        #expect(controller.errorMessage == DictationError.recordingTooShort.localizedDescription)
        #expect(!FileManager.default.fileExists(atPath: recorder.url.path))
        let calls = await recognizer.transcriptionCount
        #expect(calls == 0)
    }

    @Test
    func testFailedTranscriptionPreservesPreviousTextAndDeletesNewAudio() async {
        let recorder = StubRecorder()
        let recognizer = StubTranscriber(output: "保留这段文字。")
        let controller = DictationController(transcriber: recognizer, recorder: recorder)
        await controller.prepare()
        await controller.toggleRecording()
        await controller.toggleRecording()
        await recognizer.setTranscriptionFailure(true)
        await controller.toggleRecording()
        await controller.toggleRecording()
        #expect(controller.phase == .ready)
        #expect(controller.transcript == "保留这段文字。")
        #expect(controller.errorMessage != nil)
        #expect(!FileManager.default.fileExists(atPath: recorder.url.path))
    }

    @Test
    func testModelPreparationCanBeRetriedAndIsNotRepeatedAfterSuccess() async {
        let recognizer = StubTranscriber()
        await recognizer.setPreparationFailure(true)
        let controller = DictationController(transcriber: recognizer, recorder: StubRecorder())
        await controller.prepare()
        #expect(controller.phase == .failed)
        await recognizer.setPreparationFailure(false)
        await controller.prepare()
        await controller.prepare()
        #expect(controller.phase == .ready)
        #expect(controller.errorMessage == nil)
        let calls = await recognizer.preparationCount
        #expect(calls == 2)
    }

    @Test
    func testNoSpeechShowsRecoverableError() async {
        let recorder = StubRecorder()
        let controller = DictationController(transcriber: StubTranscriber(output: "  \n"), recorder: recorder)
        await controller.prepare()
        await controller.toggleRecording()
        await controller.toggleRecording()
        #expect(controller.phase == .ready)
        #expect(controller.errorMessage == DictationError.noSpeech.localizedDescription)
        #expect(!FileManager.default.fileExists(atPath: recorder.url.path))
    }

    @Test
    func testRecorderFailureAndShutdownReleaseCapture() async {
        let recorder = StubRecorder()
        let controller = DictationController(transcriber: StubTranscriber(), recorder: recorder)
        await controller.prepare()
        await controller.toggleRecording()
        recorder.onFailure?(DictationError.recorderUnavailable)
        #expect(controller.phase == .ready)
        #expect(!FileManager.default.fileExists(atPath: recorder.url.path))
        await controller.toggleRecording()
        controller.shutDown()
        #expect(!FileManager.default.fileExists(atPath: recorder.url.path))
    }

    @Test
    func testRepeatedClickDuringTranscriptionIsIgnoredAndShutdownDeletesPendingAudio() async {
        let recorder = StubRecorder()
        let recognizer = SuspendedTranscriber()
        let controller = DictationController(transcriber: recognizer, recorder: recorder)
        await controller.prepare()
        await controller.toggleRecording()
        let transcription = Task { await controller.toggleRecording() }
        await recognizer.waitForStart()
        #expect(controller.phase == .transcribing)
        await controller.toggleRecording()
        let calls = await recognizer.transcriptionCount
        #expect(calls == 1)
        controller.shutDown()
        #expect(!FileManager.default.fileExists(atPath: recorder.url.path))
        await recognizer.finish()
        await transcription.value
    }

    @Test
    func testLongRecordingChunksPreserveAllSamples() {
        var samples = Array(repeating: Float(0.15), count: 45 * 16_000)
        samples.replaceSubrange((19 * 16_000)..<(19 * 16_000 + 3_200), with: repeatElement(Float(0), count: 3_200))
        let chunks = SenseVoiceTranscriber.splitSamples(samples)
        #expect(chunks.count >= 3)
        #expect(chunks.allSatisfy { !$0.isEmpty && $0.count <= 20 * 16_000 })
        #expect(chunks.flatMap { $0 } == samples)
    }

    @Test
    func testBackgroundCancellationDeletesRecordingAndPreservesText() async {
        let recorder = StubRecorder()
        let controller = DictationController(transcriber: StubTranscriber(output: "保留文字"), recorder: recorder)
        await controller.prepare()
        await controller.toggleRecording()
        await controller.toggleRecording()
        await controller.toggleRecording()
        controller.cancelRecording(message: "录音已中断")
        #expect(controller.phase == .ready)
        #expect(controller.transcript == "保留文字")
        #expect(controller.errorMessage == "录音已中断")
        #expect(!FileManager.default.fileExists(atPath: recorder.url.path))
    }

    @Test
    func testLatePermissionResponseCannotStartRecordingAfterCancellation() async {
        let recorder = DelayedPermissionRecorder()
        let controller = DictationController(transcriber: StubTranscriber(), recorder: recorder)
        await controller.prepare()
        let request = Task { await controller.toggleRecording() }
        while recorder.permissionReply == nil { await Task.yield() }
        controller.cancelRecording()
        recorder.permissionReply?.resume(returning: true)
        await request.value
        #expect(controller.phase == .ready)
        #expect(!recorder.didStart)
    }
}

@MainActor
private final class DelayedPermissionRecorder: AudioRecording {
    let currentTime: TimeInterval = 0
    let level: Double = 0
    var onFailure: ((Error) -> Void)?
    var permissionReply: CheckedContinuation<Bool, Never>?
    var didStart = false
    func requestPermission() async -> Bool {
        await withCheckedContinuation { permissionReply = $0 }
    }
    func start() throws { didStart = true }
    func stop() throws -> URL { throw DictationError.recorderUnavailable }
    func discard() { }
}

private actor SuspendedTranscriber: SpeechTranscribing {
    var transcriptionCount = 0
    private var completion: CheckedContinuation<String, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?

    func prepare(progress: @escaping @Sendable (ModelPreparation) -> Void) async throws { }

    func transcribe(audioURL: URL) async throws -> String {
        transcriptionCount += 1
        return await withCheckedContinuation { continuation in
            completion = continuation
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitForStart() async {
        if completion != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish() {
        completion?.resume(returning: "测试完成")
        completion = nil
    }
}

private actor StubTranscriber: SpeechTranscribing {
    let output: String
    var preparationCount = 0
    var transcriptionCount = 0
    var failPreparation = false
    var failTranscription = false

    init(output: String = "测试文本") { self.output = output }
    func setPreparationFailure(_ value: Bool) { failPreparation = value }
    func setTranscriptionFailure(_ value: Bool) { failTranscription = value }

    func prepare(progress: @escaping @Sendable (ModelPreparation) -> Void) async throws {
        preparationCount += 1
        if failPreparation { throw URLError(.notConnectedToInternet) }
    }

    func transcribe(audioURL: URL) async throws -> String {
        transcriptionCount += 1
        guard FileManager.default.fileExists(atPath: audioURL.path) else { throw URLError(.fileDoesNotExist) }
        if failTranscription { throw URLError(.cannotDecodeContentData) }
        return output
    }
}

@MainActor
private final class StubRecorder: AudioRecording {
    var currentTime: TimeInterval = 2
    var level: Double = 0.5
    var permission = true
    var didStart = false
    var onFailure: ((Error) -> Void)?
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("mindflow-test-\(UUID().uuidString).wav")

    func requestPermission() async -> Bool { permission }
    func start() throws {
        didStart = true
        try Data("test audio placeholder".utf8).write(to: url)
    }
    func stop() throws -> URL { url }
    func discard() { try? FileManager.default.removeItem(at: url) }
}
