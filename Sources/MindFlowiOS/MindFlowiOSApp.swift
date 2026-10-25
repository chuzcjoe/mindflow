import AVFoundation
import MindFlowKit
import SwiftUI
import UIKit

@main
struct MindFlowiOSApp: App {
    @State private var controller: DictationController
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let recorder: (any AudioRecording)?
        #if DEBUG && targetEnvironment(simulator)
        recorder = ProcessInfo.processInfo.environment["MINDFLOW_SAMPLE_AUDIO"]
            .map { SimulatorSampleRecorder(input: URL(fileURLWithPath: $0)) }
        #else
        recorder = nil
        #endif
        _controller = State(initialValue: DictationController(recorder: recorder, onTranscription: { text in
            UIPasteboard.general.string = text
        }))
    }

    private var usesSampleAudio: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["MINDFLOW_SAMPLE_AUDIO"] != nil
        #else
        return false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            DictationView(controller: controller, usesSampleAudio: usesSampleAudio)
                .task {
                    // The hosted integration tests load their own real model.
                    #if DEBUG
                    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                    #endif
                    await controller.prepare()
                    #if DEBUG && targetEnvironment(simulator)
                    if usesSampleAudio && ProcessInfo.processInfo.arguments.contains("--validate-sample") {
                        await controller.toggleRecording()
                        await controller.toggleRecording()
                        writeSampleReport()
                    }
                    #endif
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        controller.cancelRecording(message: "录音已停止。回到应用后，可重新开始录音。")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
                    let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                    if value == AVAudioSession.InterruptionType.began.rawValue {
                        controller.cancelRecording(message: "录音被来电或其他音频中断，请重新录制。")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    controller.shutDown()
                }
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    private func writeSampleReport() {
        guard let runID = ProcessInfo.processInfo.environment["MINDFLOW_SAMPLE_RUN_ID"],
              UUID(uuidString: runID) != nil else { return }
        let report: [String: Any] = [
            "transcript": controller.transcript,
            "error": controller.errorMessage as Any? ?? NSNull(),
            "seconds": controller.lastTranscriptionSeconds as Any? ?? NSNull(),
            "ready": controller.phase == .ready,
            "clipboardMatchesTranscript": !controller.transcript.isEmpty
                && UIPasteboard.general.string == controller.transcript,
        ]
        do {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("mindflow-sample-\(runID).json")
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: url, options: .atomic)
        } catch { print("Sample validation report: \(error)") }
    }
    #endif
}

#if DEBUG && targetEnvironment(simulator)
/// A developer-only microphone substitute for Macs without a working input.
/// It supplies a WAV file; all model loading, decoding and UI use real code.
@MainActor
private final class SimulatorSampleRecorder: AudioRecording {
    private let input: URL
    private var recordingURL: URL?
    var currentTime: TimeInterval = 0
    var level: Double { 0.4 }
    var onFailure: ((Error) -> Void)?

    init(input: URL) { self.input = input }
    func requestPermission() async -> Bool { true }
    func start() throws {
        discard()
        let file = try AVAudioFile(forReading: input)
        currentTime = Double(file.length) / file.processingFormat.sampleRate
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mindflow-\(UUID()).wav")
        try FileManager.default.copyItem(at: input, to: url)
        recordingURL = url
    }
    func stop() throws -> URL {
        guard let url = recordingURL else { throw DictationError.recorderUnavailable }
        recordingURL = nil
        return url
    }
    func discard() {
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
    }
}
#endif
