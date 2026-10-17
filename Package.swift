// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Audiomeeter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Audiomeeter",
            targets: ["Audiomeeter"]
        )
    ],
    dependencies: [],
    targets: [
        .target(name: "VMNative", path: "Native/Realtime", publicHeadersPath: "include"),
        .executableTarget(
            name: "Audiomeeter",
            dependencies: ["VMNative"],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMIDI"),
                .linkedFramework("Accelerate"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
