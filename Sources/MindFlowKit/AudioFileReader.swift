import AVFoundation
import Foundation

/// Decode local audio to the mono, normalized 16 kHz samples used by SenseVoice.
enum AudioFileReader {
    static func samples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        AudioDiagnostics.write("source-audio", [
            "fileBytes": (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
            "sourceFrames": file.length,
            "sampleRate": file.processingFormat.sampleRate,
            "channels": file.processingFormat.channelCount,
        ])
        guard file.length > 0 else { return [] }
        guard file.length <= Int64(UInt32.max),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioFileError.invalidAudio
        }
        try readAllFrames(from: file, into: input)
        AudioDiagnostics.write("decoded-audio", ["framesRead": input.frameLength])

        if file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1 {
            return try copySamples(input)
        }

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input.format, to: format) else {
            throw AudioFileError.invalidAudio
        }
        let capacity = ceil(Double(input.frameLength) * 16_000 / input.format.sampleRate) + 1024
        guard capacity <= Double(UInt32.max),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(capacity)) else {
            throw AudioFileError.invalidAudio
        }
        var suppliedInput = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if suppliedInput {
                state.pointee = .endOfStream
                return nil
            }
            suppliedInput = true
            state.pointee = .haveData
            return input
        }
        if let error { throw error }
        AudioDiagnostics.write("resampling", ["status": status.rawValue, "outputFrames": output.frameLength])
        guard status != .error else { throw AudioFileError.invalidAudio }
        return try copySamples(output)
    }

    private static func copySamples(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { throw AudioFileError.invalidAudio }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private static func readAllFrames(from file: AVAudioFile, into buffer: AVAudioPCMBuffer) throws {
        guard let chunk = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: min(buffer.frameCapacity, 16_384)),
              let destination = buffer.floatChannelData,
              let source = chunk.floatChannelData else { throw AudioFileError.invalidAudio }
        var copied: AVAudioFrameCount = 0
        while copied < buffer.frameCapacity {
            // AVAudioFile may return fewer frames than requested before EOF.
            // In particular, a 16000-frame Float32 WAV can be read as 15360+640.
            try file.read(into: chunk, frameCount: min(chunk.frameCapacity, buffer.frameCapacity - copied))
            guard chunk.frameLength > 0 else { break }
            for channel in 0..<Int(buffer.format.channelCount) {
                destination[channel].advanced(by: Int(copied)).update(from: source[channel], count: Int(chunk.frameLength))
            }
            copied += chunk.frameLength
        }
        buffer.frameLength = copied
    }
}

private enum AudioFileError: LocalizedError {
    case invalidAudio
    var errorDescription: String? { "无法读取这段录音，请重新录制。" }
}
