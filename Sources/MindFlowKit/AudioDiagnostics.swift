import Foundation

/// Opt-in local troubleshooting metadata: never stores audio or dictated text.
enum AudioDiagnostics {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--audio-diagnostics") }

    static func write(_ name: String, _ fields: [String: Any]) {
        guard enabled else { return }
        do {
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MindFlow/AudioDiagnostics", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = fields
            values["updatedAt"] = Date().timeIntervalSince1970
            let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys, .prettyPrinted])
            try data.write(to: directory.appendingPathComponent(name + ".json"), options: .atomic)
        } catch { /* Diagnostics must not interfere with recording. */ }
    }

    static func input(_ samples: [Float]) {
        guard enabled else { return }
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        let power = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        write("recognition-input", [
            "sampleCount": samples.count,
            "sampleRate": 16_000,
            "duration": Double(samples.count) / 16_000,
            "peak": peak,
            "rms": samples.isEmpty ? 0 : sqrt(power / Double(samples.count)),
        ])
    }
}
