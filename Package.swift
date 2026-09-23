// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sonar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Sonar",
            path: ".",
            sources: ["work/Sonar"],
            resources: [
                .copy("assets/zoom"),
                .copy("assets/gallery"),
                .copy("assets/paper/SoundWave.pdf"),
                .copy("assets/sonar.png"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
