import AVFoundation
import Foundation

@MainActor
public protocol AudioRecording: AnyObject {
    var currentTime: TimeInterval { get }
    var level: Double { get }
    var onFailure: ((Error) -> Void)? { get set }
    func requestPermission() async -> Bool
    func start() throws
    func stop() throws -> URL
    func discard()
}

@MainActor
public final class AudioRecorder: NSObject, AudioRecording, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    #if os(iOS)
    private var sessionIsActive = false
    #endif
    public var onFailure: ((Error) -> Void)?

    public var currentTime: TimeInterval { recorder?.currentTime ?? 0 }

    public var level: Double {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        return min(1, max(0, (Double(recorder.averagePower(forChannel: 0)) + 55) / 55))
    }

    public override init() { super.init() }

    public func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    public func start() throws {
        discard()
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
        sessionIsActive = true
        #endif
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mindflow-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        recordingURL = url
        do {
            let capture = try AVAudioRecorder(url: url, settings: settings)
            capture.delegate = self
            capture.isMeteringEnabled = true
            recorder = capture
            guard capture.prepareToRecord(), capture.record() else {
                throw DictationError.recorderUnavailable
            }
        } catch {
            discard()
            throw error
        }
    }

    public func stop() throws -> URL {
        guard let recorder, let url = recordingURL else {
            throw DictationError.recorderUnavailable
        }
        recorder.stop()
        recorder.delegate = nil
        self.recorder = nil
        recordingURL = nil
        deactivateSession()
        return url
    }

    public func discard() {
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        deactivateSession()
    }

    private func deactivateSession() {
        #if os(iOS)
        guard sessionIsActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionIsActive = false
        #endif
    }

    public nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            self?.onFailure?(error ?? DictationError.recorderUnavailable)
        }
    }

    public nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard !flag else { return }
        Task { @MainActor [weak self] in
            self?.onFailure?(DictationError.recorderUnavailable)
        }
    }
}
