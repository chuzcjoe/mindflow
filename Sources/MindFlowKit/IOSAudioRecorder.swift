#if os(iOS)
import AVFoundation
import Foundation

/// Capture hardware PCM directly, and close the file before recognition reads it.
@MainActor
public final class AudioRecorder: AudioRecording {
    public var onFailure: ((Error) -> Void)?
    private var engine: AVAudioEngine?
    private var sink: MicrophonePCMSink?
    private var recordingURL: URL?
    private var sessionIsActive = false
    private var sampleRate = 48_000.0

    public init() {}
    public var currentTime: TimeInterval { Double(sink?.frames ?? 0) / sampleRate }
    public var level: Double { sink?.level ?? 0 }

    public func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    public func start() throws {
        discard()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            sessionIsActive = true
            guard let microphone = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
                throw DictationError.recorderUnavailable
            }
            try session.setPreferredInput(microphone)
            guard !AVAudioApplication.shared.isInputMuted else { throw DictationError.microphoneMuted }
            let capture = AVAudioEngine()
            let input = capture.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0,
                  format.commonFormat == .pcmFormatFloat32 else { throw DictationError.recorderUnavailable }
            sampleRate = format.sampleRate
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("mindflow-\(UUID()).caf")
            recordingURL = url
            let writer = try MicrophonePCMSink(url: url, format: format)
            sink = writer
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                do { try writer.append(buffer) }
                catch {
                    Task { @MainActor [weak self] in self?.onFailure?(error) }
                }
            }
            engine = capture
            capture.prepare()
            try capture.start()
            AudioDiagnostics.write("capture-session", [
                "captureAPI": "AVAudioEngine",
                "recordPermission": AVAudioApplication.shared.recordPermission.rawValue,
                "inputMuted": AVAudioApplication.shared.isInputMuted,
                "category": session.category.rawValue,
                "mode": session.mode.rawValue,
                "sampleRate": format.sampleRate,
                "inputChannels": format.channelCount,
                "inputPorts": session.currentRoute.inputs.map { $0.portType.rawValue },
            ])
        } catch {
            discard()
            throw error
        }
    }

    public func stop() throws -> URL {
        guard let engine, let sink, let url = recordingURL else { throw DictationError.recorderUnavailable }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sink.finish()
        let frames = sink.frames
        AudioDiagnostics.write("capture-file", [
            "framesWritten": frames,
            "sampleRate": sampleRate,
            "peak": sink.peak,
            "fileBytes": (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
        ])
        self.engine = nil
        self.sink = nil
        recordingURL = nil
        deactivateSession()
        guard frames > 0 else {
            try? FileManager.default.removeItem(at: url)
            throw DictationError.silentRecording
        }
        return url
    }

    public func discard() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        sink?.finish()
        engine = nil
        sink = nil
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        deactivateSession()
    }

    private func deactivateSession() {
        guard sessionIsActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionIsActive = false
    }
}

/// The audio tap and UI access this object on different threads. The lock also
/// makes closing the file wait for the final write, before the model reads it.
private final class MicrophonePCMSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var frameCount: AVAudioFramePosition = 0
    private var meter = 0.0
    private var peakValue = Float(0)

    init(url: URL, format: AVAudioFormat) throws {
        file = try AVAudioFile(forWriting: url, settings: format.settings,
                               commonFormat: format.commonFormat, interleaved: format.isInterleaved)
    }

    var frames: AVAudioFramePosition { lock.withLock { frameCount } }
    var level: Double { lock.withLock { meter } }
    var peak: Float { lock.withLock { peakValue } }

    func append(_ buffer: AVAudioPCMBuffer) throws {
        try lock.withLock {
            guard let file, buffer.frameLength > 0 else { return }
            try file.write(from: buffer)
            frameCount += AVAudioFramePosition(buffer.frameLength)
            guard let values = buffer.floatChannelData?[0] else { return }
            var power = 0.0
            for index in 0..<Int(buffer.frameLength) {
                let value = values[index]
                power += Double(value) * Double(value)
                peakValue = max(peakValue, abs(value))
            }
            let rms = sqrt(power / Double(buffer.frameLength))
            let db = 20 * log10(max(rms, 0.000_000_01))
            meter = min(1, max(0, (db + 55) / 55))
        }
    }

    func finish() {
        lock.withLock {
            if #available(iOS 18.0, *) { file?.close() }
            file = nil
        }
    }
}
#endif
