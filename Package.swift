// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Redactor",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "RedactorCore"),
        .executableTarget(name: "Redactor", dependencies: ["RedactorCore"]),
        .testTarget(name: "RedactorCoreTests", dependencies: ["RedactorCore"]),
    ]
)
