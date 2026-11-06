// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LabSelectionNative",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LabSelectionNative", targets: ["LabSelectionNative"]),
               .executable(name: "LabSelectionNativeValidation", targets: ["LabSelectionNativeValidation"])],
    targets: [
        .target(name: "ChordAudioBoundary", linkerSettings: [.linkedFramework("AVFAudio")]),
        .target(name: "LabSelectionNative", dependencies: ["ChordAudioBoundary"]),
        .executableTarget(name: "LabSelectionNativeValidation", dependencies: ["LabSelectionNative"], path: "Validation"),
        .testTarget(name: "LabSelectionNativeTests", dependencies: ["LabSelectionNative"])
    ],
    swiftLanguageVersions: [.v5]
)
