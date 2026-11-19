// swift-tools-version:5.9
import PackageDescription

// CleanKit: skanowanie i bezpieczne czyszczenie cache. Bez UI, testowalne przez `swift test`.
let package = Package(
    name: "CleanKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CleanKit", targets: ["CleanKit"]), .executable(name: "opencleaner-mcp", targets: ["opencleaner-mcp"])],
    targets: [
        .target(name: "CleanKit"),
        .executableTarget(name: "opencleaner-mcp", dependencies: ["CleanKit"]),
        .testTarget(name: "CleanKitTests", dependencies: ["CleanKit"]),
    ]
)
