import Foundation

// Prepare the approved artwork for Xcode without redrawing the icon.
// Usage: swift scripts/make-ios-icon.swift [output.png] [master.png]
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appendingPathComponent("Sources/MindFlowiOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let source = CommandLine.arguments.count > 2
    ? URL(fileURLWithPath: CommandLine.arguments[2])
    : root.appendingPathComponent("Support/Icons/MindFlow-iOS-master.png")

try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let resize = Process()
resize.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
resize.arguments = ["-s", "format", "png", "-z", "1024", "1024", source.path, "--out", output.path]
try resize.run()
resize.waitUntilExit()
guard resize.terminationStatus == 0 else { exit(resize.terminationStatus) }
print("Prepared 1024 × 1024 opaque iOS icon: \(output.path)")
