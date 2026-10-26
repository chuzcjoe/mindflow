import AVFoundation
import Foundation
import Testing
@testable import MindFlowKit

struct AudioFileReaderTests {
    @Test
    func testHardwareRatePCM16RecordingConvertsWithoutLosingSignal() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mindflow-hardware-pcm-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        let channel = try #require(buffer.floatChannelData?[0])
        for i in 0..<48_000 { channel[i] = Float(sin(Double(i) * 2 * .pi * 440 / 48_000)) * 0.25 }
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
            if #available(macOS 15.0, iOS 18.0, *) { file.close() }
        }
        let samples = try AudioFileReader.samples(from: url)
        #expect(abs(samples.count - 16_000) <= 2)
        let peak = samples.map { abs($0) }.max() ?? 0
        #expect(peak > 0.2 && peak < 0.3)
    }

    @Test
    func testNativeRecordingPreservesNormalizedSamples() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mindflow-pcm-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = 16_000
        let channel = try #require(buffer.floatChannelData?[0])
        for index in 0..<16_000 { channel[index] = index.isMultiple(of: 2) ? 0.25 : -0.5 }
        try write(buffer, to: url)
        let samples = try AudioFileReader.samples(from: url)
        try #require(samples.count == 16_000)
        #expect(samples[0] == 0.25)
        #expect(samples[1] == -0.5)
        #expect(samples[15_998] == 0.25)
        #expect(samples[15_999] == -0.5)
    }

    @Test
    func testStereoHighSampleRateAudioIsConvertedToMono16kHz() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mindflow-resample-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        let channels = try #require(buffer.floatChannelData)
        for index in 0..<48_000 {
            let value = Float(sin(Double(index) * 2 * .pi * 440 / 48_000)) * 0.25
            channels[0][index] = value
            channels[1][index] = value
        }
        try write(buffer, to: url)
        let samples = try AudioFileReader.samples(from: url)
        #expect(abs(samples.count - 16_000) <= 2)
        let peak = samples.map { abs($0) }.max() ?? 0
        #expect(peak > 0.2 && peak < 0.3)
    }

    private func write(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        // Closing this scope finalizes the WAV header before the reader opens it.
        try autoreleasepool {
            var settings = buffer.format.settings
            settings[AVLinearPCMIsNonInterleaved] = false
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
            if #available(macOS 15.0, iOS 18.0, *) { file.close() }
        }
    }
}
