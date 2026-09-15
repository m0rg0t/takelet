// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Takelet",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Takelet", targets: ["TakeletApp"]),
        .executable(name: "takelet-analyze", targets: ["TakeletAnalyze"]),
        .executable(name: "takelet-media-check", targets: ["MediaCheck"])
    ],
    targets: [
        .target(name: "AnalysisCore"),
        .target(name: "ProjectCore"),
        .target(name: "MediaEngine", dependencies: ["ProjectCore"]),
        .executableTarget(name: "TakeletApp", dependencies: ["ProjectCore", "MediaEngine"], linkerSettings: [.linkedFramework("AVKit")]),
        .executableTarget(name: "MediaCheck", dependencies: ["ProjectCore", "MediaEngine"]),
        .executableTarget(name: "TakeletAnalyze", dependencies: ["AnalysisCore"]),
        .testTarget(name: "AnalysisCoreTests", dependencies: ["AnalysisCore"]),
        .testTarget(name: "ProjectCoreTests", dependencies: ["ProjectCore"])
    ]
)
