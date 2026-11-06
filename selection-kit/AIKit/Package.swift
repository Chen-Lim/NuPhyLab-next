// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LabSelectionAI",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LabSelectionAI", targets: ["LabSelectionAI"])],
    targets: [
        .target(name: "LabSelectionAI"),
        .testTarget(name: "LabSelectionAITests", dependencies: ["LabSelectionAI"])
    ],
    swiftLanguageVersions: [.v5]
)
