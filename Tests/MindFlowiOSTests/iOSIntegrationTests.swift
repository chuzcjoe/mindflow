import AVFoundation
import XCTest
@testable import MindFlowKit

@MainActor
final class iOSIntegrationTests: XCTestCase {
    func testRealSenseVoiceRecognizesMandarinAndEnglishThroughRecordingFlow() async throws {
        let bundle = Bundle(for: Self.self)
        let inputs = try ["mandarin", "english"].map { name in
            try XCTUnwrap(bundle.url(forResource: name, withExtension: "wav"))
        }
        let recorder = FixtureRecorder(inputs: inputs)
        let controller = DictationController(transcriber: SenseVoiceTranscriber(), recorder: recorder)
        await controller.prepare()
        XCTAssertEqual(controller.phase, .ready, controller.errorMessage ?? "Model preparation failed")
        for expected in ["交易", "fellow Americans"] {
            await controller.toggleRecording()
            XCTAssertEqual(controller.phase, .recording)
            await controller.toggleRecording()
            XCTAssertEqual(controller.phase, .ready)
            XCTAssertNil(controller.errorMessage)
            XCTAssertTrue(controller.transcript.contains(expected), controller.transcript)
            XCTAssertNotNil(controller.lastTranscriptionSeconds)
            XCTAssertFalse(FileManager.default.fileExists(atPath: recorder.lastURL!.path))
            print("REAL_IOS_SENSEVOICE: \(controller.transcript)")
        }
        controller.shutDown()
    }

    func testNativeIOSAudioSessionRecords16kMonoAndReleasesTemporaryAudio() async throws {
        let recorder = AudioRecorder()
        defer { recorder.discard() }
        let granted = await recorder.requestPermission()
        XCTAssertTrue(granted, "Allow microphone access for the simulator test host.")
        guard granted else { return }
        try recorder.start()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playAndRecord)
        let hardwareRate = AVAudioSession.sharedInstance().sampleRate
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertGreaterThan(recorder.currentTime, 0.3)
        let url = try recorder.stop()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.processingFormat.sampleRate, hardwareRate)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        XCTAssertGreaterThan(file.length, 4_800)
        let samples = try AudioFileReader.samples(from: url)
        XCTAssertEqual(Double(samples.count), Double(file.length) * 16_000 / hardwareRate, accuracy: 2)
        try recorder.start()
        recorder.discard()
    }
}

/// Only audio capture is substituted; decoding uses the real iOS ONNX engine.
@MainActor
private final class FixtureRecorder: AudioRecording {
    var currentTime: TimeInterval = 0
    var level = 0.5
    var onFailure: ((Error) -> Void)?
    private var inputs: [URL]
    private(set) var lastURL: URL?

    init(inputs: [URL]) { self.inputs = inputs }
    func requestPermission() async -> Bool { true }
    func start() throws {
        let input = inputs.removeFirst()
        let file = try AVAudioFile(forReading: input)
        currentTime = Double(file.length) / file.processingFormat.sampleRate
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mindflow-ios-test-\(UUID()).wav")
        try FileManager.default.copyItem(at: input, to: url)
        lastURL = url
    }
    func stop() throws -> URL { try XCTUnwrap(lastURL) }
    func discard() {
        if let lastURL { try? FileManager.default.removeItem(at: lastURL) }
    }
}
