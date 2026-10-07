// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LpxExplorer",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LpxCore", targets: ["LpxCore"]),
        .executable(name: "LpxExplorer", targets: ["LpxExplorer"]),
    ],
    targets: [
        // Read-only parser + scanner. No UI, no writes to .logicx bundles.
        .target(name: "LpxCore"),
        .executableTarget(name: "LpxExplorer", dependencies: ["LpxCore"]),
        // Read-only CLI for timing/validating the scanner against real folders.
        .executableTarget(name: "lpx-scan", dependencies: ["LpxCore"]),
        .testTarget(name: "LpxCoreTests", dependencies: ["LpxCore"]),
    ]
)
