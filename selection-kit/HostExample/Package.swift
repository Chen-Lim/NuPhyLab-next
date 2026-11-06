// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LabSelectionHostExample",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LabSelectionHostExample", targets: ["LabSelectionHostExample"])],
    dependencies: [.package(path: "../AIKit"), .package(path: "../NativeKit"), .package(path: "../FlowKit")],
    targets: [.target(name: "LabSelectionHostExample", dependencies: [
        .product(name: "LabSelectionAI", package: "AIKit"),
        .product(name: "LabSelectionNative", package: "NativeKit"),
        .product(name: "LabSelectionFlow", package: "FlowKit")
    ])],
    swiftLanguageVersions: [.v5]
)
