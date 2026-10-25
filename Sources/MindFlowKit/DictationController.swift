import Foundation
import Observation

public enum DictationPhase: Equatable {
    case preparing
    case ready
    case requestingPermission
    case recording
    case transcribing
    case failed
}

@MainActor @Observable
public final class DictationController {
    public private(set) var phase: DictationPhase = .preparing
    public private(set) var preparationMessage = "正在准备语音模型…"
    public private(set) var downloadProgress: Double?
    public private(set) var transcript = ""
    public private(set) var errorMessage: String?
    public private(set) var needsMicrophonePermission = false
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var audioLevels: [Double] = Array(repeating: 0.08, count: 35)
    public private(set) var lastTranscriptionSeconds: Double?

    @ObservationIgnored private let transcriber: any SpeechTranscribing
    @ObservationIgnored private let recorder: any AudioRecording
    @ObservationIgnored private let onTranscription: @MainActor (String) -> Void
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var didPrepare = false
    @ObservationIgnored private var pendingAudioURL: URL?
    @ObservationIgnored private var recordingRequestID = UUID()

    public init(
        transcriber: any SpeechTranscribing = SenseVoiceTranscriber(),
        recorder: (any AudioRecording)? = nil,
        onTranscription: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.transcriber = transcriber
        self.recorder = recorder ?? AudioRecorder()
        self.onTranscription = onTranscription
        self.recorder.onFailure = { [weak self] error in
            guard let self, self.phase == .recording else { return }
            self.stopMeter()
            self.recorder.discard()
            self.errorMessage = error.localizedDescription
            self.phase = .ready
        }
    }

    public func prepare() async {
        guard !didPrepare else { return }
        didPrepare = true
        phase = .preparing
        errorMessage = nil
        downloadProgress = nil
        preparationMessage = "正在准备 SenseVoice…"
        do {
            try await transcriber.prepare { [weak self] progress in
                Task { @MainActor in
                    guard let self, self.phase == .preparing else { return }
                    switch progress {
                    case .downloading(let fraction):
                        self.preparationMessage = "首次使用，正在下载 SenseVoice（约 239 MB）"
                        self.downloadProgress = min(1, max(0, fraction))
                    case .loading:
                        self.preparationMessage = "正在加载 SenseVoice…"
                        self.downloadProgress = nil
                    }
                }
            }
            phase = .ready
            downloadProgress = nil
        } catch {
            phase = .failed
            didPrepare = false
            errorMessage = "SenseVoice 准备失败，请检查网络连接后重试。\n\(error.localizedDescription)"
        }
    }

    public func toggleRecording() async {
        switch phase {
        case .ready: await startRecording()
        case .recording: await finishRecording()
        default: break
        }
    }

    private func startRecording() async {
        let requestID = UUID()
        recordingRequestID = requestID
        phase = .requestingPermission
        errorMessage = nil
        needsMicrophonePermission = false
        let granted = await recorder.requestPermission()
        guard recordingRequestID == requestID, phase == .requestingPermission else { return }
        guard granted else {
            errorMessage = DictationError.microphoneDenied.localizedDescription
            needsMicrophonePermission = true
            phase = .ready
            return
        }
        do {
            try recorder.start()
            elapsed = 0
            audioLevels = Array(repeating: 0.08, count: 35)
            phase = .recording
            startMeter()
        } catch {
            recorder.discard()
            errorMessage = error.localizedDescription
            phase = .ready
        }
    }

    private func finishRecording() async {
        // Change state before awaiting anything, preventing double clicks from starting another job.
        phase = .transcribing
        elapsed = recorder.currentTime
        stopMeter()
        do {
            let fileURL = try recorder.stop()
            pendingAudioURL = fileURL
            defer {
                try? FileManager.default.removeItem(at: fileURL)
                pendingAudioURL = nil
            }
            guard elapsed >= 0.35 else { throw DictationError.recordingTooShort }
            let started = ProcessInfo.processInfo.systemUptime
            let text = try await transcriber.transcribe(audioURL: fileURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw DictationError.noSpeech }
            transcript = text
            lastTranscriptionSeconds = ProcessInfo.processInfo.systemUptime - started
            // Publish each successful recording, including identical transcripts.
            // App entry points supply their platform's clipboard implementation.
            onTranscription(text)
        } catch {
            // Preserve the last successful transcript if the new recording fails.
            recorder.discard()
            errorMessage = error.localizedDescription
        }
        phase = .ready
    }

    /// iOS stops capture when entering the background or receiving a call.
    /// Invalidating the request also prevents a late permission response from
    /// starting capture after the app has already left the foreground.
    public func cancelRecording(message: String? = nil) {
        guard phase == .recording || phase == .requestingPermission else { return }
        recordingRequestID = UUID()
        stopMeter()
        recorder.discard()
        elapsed = 0
        audioLevels = Array(repeating: 0.08, count: 35)
        errorMessage = message
        phase = .ready
    }

    public func shutDown() {
        cancelRecording()
        stopMeter()
        recorder.discard()
        if let pendingAudioURL { try? FileManager.default.removeItem(at: pendingAudioURL) }
        pendingAudioURL = nil
    }

    private func startMeter() {
        meterTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.phase == .recording else { return }
                self.elapsed = self.recorder.currentTime
                self.audioLevels.removeFirst()
                self.audioLevels.append(max(0.08, self.recorder.level))
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
    }

    private func stopMeter() {
        meterTask?.cancel()
        meterTask = nil
    }
}
