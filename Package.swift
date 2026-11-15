// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SnippingWerkzeug",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "SnippingWerkzeug",
            path: "Sources/SnippingWerkzeug"
        )
    ],
    swiftLanguageModes: [.v5]
)
