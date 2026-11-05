// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CloakCapture",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CloakCapture", targets: ["CloakCapture"])],
    targets: [
        .executableTarget(name: "CloakCapture")
    ],
    swiftLanguageModes: [.v5]
)
