// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoicemeeterMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "VoicemeeterMac",
            targets: ["VoicemeeterMac"]
        )
    ],
    dependencies: [],
    targets: [
        .target(name: "VMNative", path: "Native/Realtime", publicHeadersPath: "include"),
        .executableTarget(
            name: "VoicemeeterMac",
            dependencies: ["VMNative"],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Accelerate"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
