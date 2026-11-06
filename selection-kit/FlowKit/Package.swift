// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LabSelectionFlow",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LabSelectionFlow", targets: ["LabSelectionFlow"]),
               .executable(name: "FlowChecks", targets: ["FlowChecks"])],
    dependencies: [.package(path: "../AIKit")],
    targets: [
        .target(name: "LabSelectionFlow", dependencies: [.product(name: "LabSelectionAI", package: "AIKit")]),
        .testTarget(name: "LabSelectionFlowTests", dependencies: ["LabSelectionFlow"]),
        .executableTarget(name: "FlowChecks", dependencies: ["LabSelectionFlow"], path: "Checks")
    ],
    swiftLanguageVersions: [.v5]
)
