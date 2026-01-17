// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "swift",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "swift",
            type: .static,
            targets: ["swift"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "swift",
            dependencies: [],
            path: ".",
            sources: ["Capture.swift", "Speech.swift"],
            swiftSettings: [
                .unsafeFlags(["-suppress-warnings"])
            ],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation")
            ]
        )
    ]
)
