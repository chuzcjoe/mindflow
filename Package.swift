// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MindFlow",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MindFlowKit", type: .static, targets: ["MindFlowKit"]),
        .executable(name: "MindFlow", targets: ["MindFlow"]),
        .executable(name: "MindFlowCheck", targets: ["MindFlowCheck"]),
    ],
    dependencies: [
        .package(url: "https://github.com/k2-fsa/sherpa-onnx.git", exact: "1.13.8"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "1.15.0"),
    ],
    targets: [
        .target(
            name: "MindFlowKit",
            dependencies: [
                .product(name: "sherpa-onnx", package: "sherpa-onnx"),
            ]
        ),
        .executableTarget(name: "MindFlow", dependencies: [
            "MindFlowKit",
            .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
        ]),
        .executableTarget(name: "MindFlowCheck", dependencies: ["MindFlowKit"]),
        .testTarget(name: "MindFlowKitTests", dependencies: ["MindFlowKit"]),
        .testTarget(name: "MindFlowAppTests", dependencies: ["MindFlow", "MindFlowKit"]),
    ]
)
