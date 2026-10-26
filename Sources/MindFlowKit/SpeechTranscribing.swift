import Foundation

public enum ModelPreparation: Sendable {
    case downloading(Double)
    case loading
}

public protocol SpeechTranscribing: Sendable {
    func prepare(progress: @escaping @Sendable (ModelPreparation) -> Void) async throws
    func transcribe(audioURL: URL) async throws -> String
}

public enum DictationError: LocalizedError {
    case modelNotReady
    case microphoneDenied
    case recorderUnavailable
    case recordingTooShort
    case noSpeech
    case silentRecording
    case microphoneMuted

    public var errorDescription: String? {
        switch self {
        case .modelNotReady: return "语音模型尚未准备好，请稍后重试。"
        case .microphoneDenied:
            #if os(iOS)
            return "请在 iPhone 的设置中，允许 MindFlow 使用麦克风。"
            #else
            return "请在系统设置 → 隐私与安全性 → 麦克风中，允许 MindFlow 使用麦克风。"
            #endif
        case .recorderUnavailable: return "无法开始录音，请检查麦克风是否已连接且可用。"
        case .recordingTooShort: return "录音太短了，请点击按钮后说一句话，再点击结束。"
        case .noSpeech: return "没有识别到语音，请靠近麦克风再试一次。"
        case .silentRecording:
            #if os(iOS)
            return "没有录到声音。若正在使用 Mac 的 Device Hub 预览或 iPhone 镜像，请先停止屏幕共享，再直接在手机上录音。"
            #else
            return "没有录到声音，请检查麦克风是否静音、被遮挡或被其他应用占用。"
            #endif
        case .microphoneMuted: return "系统已将 MindFlow 的麦克风静音，请取消静音后重新录音。"
        }
    }
}
