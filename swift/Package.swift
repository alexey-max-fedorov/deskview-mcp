// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeskviewCapture",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "DeskviewCapture",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/DeskviewCapture"
        ),
        .testTarget(
            name: "DeskviewCaptureTests",
            dependencies: ["DeskviewCapture"],
            path: "Tests/DeskviewCaptureTests"
        )
    ]
)
