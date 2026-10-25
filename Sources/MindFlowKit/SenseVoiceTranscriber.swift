import CryptoKit
import Foundation
import SherpaOnnx
import SherpaOnnxC

/// Non-autoregressive CTC recognition on the CPU, using the 239 MB INT8 model.
/// Inference stays on this actor so native decoding never blocks the UI thread.
public actor SenseVoiceTranscriber: SpeechTranscribing {
    private static let repository = "csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
    private static let revision = "2365baeacb507f821a0c8120fcee3d484dba7a07"
    private static let artifacts: [(name: String, bytes: Int, sha256: String)] = [
        ("model.int8.onnx", 239_233_841, "c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51"),
        ("tokens.txt", 315_894, "f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc"),
    ]
    private let storageURL: URL
    private var engine: SenseVoiceEngine?

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("MindFlow/Models/SenseVoice", isDirectory: true)
    }

    public func prepare(progress: @escaping @Sendable (ModelPreparation) -> Void) async throws {
        guard engine == nil else { return }
        // Keep the existing cache layout so upgrading needs no model download.
        let folder = storageURL.appendingPathComponent("models/\(Self.repository)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let totalBytes = Self.artifacts.reduce(0) { $0 + $1.bytes }
        var completedBytes = 0
        for artifact in Self.artifacts {
            let url = folder.appendingPathComponent(artifact.name)
            if !Self.isValid(url, bytes: artifact.bytes, digest: artifact.sha256) {
                let completedBeforeFile = completedBytes
                progress(.downloading(Double(completedBytes) / Double(totalBytes)))
                let delegate = ModelDownloadProgress { written in
                    let completed = completedBeforeFile + min(artifact.bytes, Int(written))
                    progress(.downloading(Double(completed) / Double(totalBytes)))
                }
                let remote = URL(string: "https://huggingface.co/\(Self.repository)/resolve/\(Self.revision)/\(artifact.name)")!
                let (temporaryURL, response) = try await URLSession.shared.download(from: remote, delegate: delegate)
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw SenseVoiceError.downloadFailed
                }
                guard Self.isValid(temporaryURL, bytes: artifact.bytes, digest: artifact.sha256) else {
                    throw SenseVoiceError.invalidModelFile(artifact.name)
                }
                // Only publish fully verified files. An interrupted download can
                // never be mistaken for a complete model on the next startup.
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: url)
            }
            completedBytes += artifact.bytes
        }

        progress(.loading)
        for artifact in Self.artifacts {
            guard Self.isValid(folder.appendingPathComponent(artifact.name), bytes: artifact.bytes, digest: artifact.sha256) else {
                throw SenseVoiceError.invalidModelFile(artifact.name)
            }
        }
        engine = try SenseVoiceEngine(folder: folder)
    }

    public func transcribe(audioURL: URL) async throws -> String {
        guard let engine else { throw DictationError.modelNotReady }
        let samples = try AudioFileReader.samples(from: audioURL)
        guard !samples.isEmpty else { return "" }
        // Bound the attention workload for longer recordings. Split near a quiet
        // boundary when possible, so word endings are not cut at a fixed interval.
        let chunks = Self.splitSamples(samples)
        var texts: [String] = []
        for chunk in chunks {
            try Task.checkCancellation()
            let text = try engine.decode(samples: chunk)
                .replacingOccurrences(of: "<\\|[^>]*\\|>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { texts.append(text) }
        }
        return texts.joined(separator: " ")
    }

    private static func isValid(_ url: URL, bytes: Int, digest: String) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), values.fileSize == bytes,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return actual == digest
    }

    /// 20-second chunks, with a low-energy 100 ms boundary in the last 2 seconds.
    static func splitSamples(_ samples: [Float]) -> [[Float]] {
        let limit = 20 * 16_000
        let window = 1_600
        var chunks: [[Float]] = []
        var start = 0
        while samples.count - start > limit {
            let end = start + limit
            var boundary = end
            var lowestEnergy = Float.greatestFiniteMagnitude
            for position in stride(from: end - 2 * 16_000, through: end - window, by: window) {
                let energy = samples[position..<(position + window)].reduce(Float(0)) { $0 + $1 * $1 }
                if energy < lowestEnergy {
                    lowestEnergy = energy
                    boundary = position + window / 2
                }
            }
            chunks.append(Array(samples[start..<boundary]))
            start = boundary
        }
        if start < samples.count { chunks.append(Array(samples[start...])) }
        return chunks
    }
}

private enum SenseVoiceError: LocalizedError {
    case downloadFailed
    case invalidModelFile(String)
    case initializationFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .downloadFailed: return "SenseVoice 模型下载失败，请检查网络连接后重试。"
        case .invalidModelFile(let name): return "SenseVoice 模型文件不完整（\(name)），请重试下载。"
        case .initializationFailed: return "SenseVoice 加载失败，请关闭其他占用内存的应用后重试。"
        case .decodingFailed: return "SenseVoice 无法识别这段录音，请重试。"
        }
    }
}

private final class ModelDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let update: @Sendable (Int64) -> Void

    init(update: @escaping @Sendable (Int64) -> Void) { self.update = update }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        update(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) { }
}

/// Use the C API for fallible allocation, instead of Swift helpers that fatalError
/// on failure. Native streams/results are released after every recording.
private final class SenseVoiceEngine {
    private let recognizer: OpaquePointer

    init(folder: URL) throws {
        let handle: OpaquePointer? = autoreleasepool {
            let senseVoice = sherpaOnnxOfflineSenseVoiceModelConfig(
                model: folder.appendingPathComponent("model.int8.onnx").path,
                language: "auto",
                useInverseTextNormalization: true
            )
            let model = sherpaOnnxOfflineModelConfig(
                tokens: folder.appendingPathComponent("tokens.txt").path,
                numThreads: min(4, ProcessInfo.processInfo.activeProcessorCount),
                provider: "cpu",
                senseVoice: senseVoice
            )
            var config = sherpaOnnxOfflineRecognizerConfig(
                featConfig: sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80),
                modelConfig: model
            )
            return SherpaOnnxCreateOfflineRecognizer(&config)
        }
        guard let handle else { throw SenseVoiceError.initializationFailed }
        recognizer = handle
    }

    deinit { SherpaOnnxDestroyOfflineRecognizer(recognizer) }

    func decode(samples: [Float]) throws -> String {
        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
            throw SenseVoiceError.decodingFailed
        }
        defer { SherpaOnnxDestroyOfflineStream(stream) }
        samples.withUnsafeBufferPointer { buffer in
            SherpaOnnxAcceptWaveformOffline(stream, 16_000, buffer.baseAddress, Int32(buffer.count))
        }
        SherpaOnnxDecodeOfflineStream(recognizer, stream)
        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else {
            throw SenseVoiceError.decodingFailed
        }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
        return result.pointee.text.map { String(cString: $0) } ?? ""
    }
}
