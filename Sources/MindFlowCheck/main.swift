import Darwin
import Foundation
import MindFlowKit

@main
struct MindFlowCheck {
    static func main() async {
        setbuf(stdout, nil)
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("Check failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        var paths = Array(CommandLine.arguments.dropFirst())
        var cacheURL: URL?
        if paths.first == "--cache-dir" {
            guard paths.count >= 3 else { throw CheckError.invalidArguments }
            cacheURL = URL(fileURLWithPath: paths[1], isDirectory: true)
            paths.removeFirst(2)
        }
        guard !paths.contains(where: { $0.hasPrefix("--") }) else { throw CheckError.invalidArguments }
        guard !paths.isEmpty else {
            print("Usage: swift run MindFlowCheck [--cache-dir <directory>] <audio.wav> [audio2.wav ...]")
            return
        }
        let transcriber = SenseVoiceTranscriber(storageURL: cacheURL)
        print("=== SenseVoiceSmall INT8 ===")
        try await transcriber.prepare { stage in
            switch stage {
            case .downloading(let fraction):
                if fraction == 0 { print("Downloading 239 MB SenseVoice model…") }
            case .loading: print("Loading SenseVoice…")
            }
        }
        for path in paths {
            let started = ProcessInfo.processInfo.systemUptime
            let text = try await transcriber.transcribe(audioURL: URL(fileURLWithPath: path))
            let seconds = ProcessInfo.processInfo.systemUptime - started
            guard !text.isEmpty else { throw DictationError.noSpeech }
            print("\(URL(fileURLWithPath: path).lastPathComponent) [\(String(format: "%.3f", seconds)) s]:\n\(text)\n")
        }
    }
}

private enum CheckError: LocalizedError {
    case invalidArguments
    var errorDescription: String? { "Usage: MindFlowCheck [--cache-dir <directory>] <audio.wav> [audio2.wav ...]" }
}
